-- ============================================================================
-- Matrix-Vector-Activation Unit (FINN-style naming) -- script section 4,
-- "Unrolling & Folding". Computes y = act(W*x + b), W is MH x MW.
--   PE   = output neurons computed in parallel  (unrolls the MH loop)
--   SIMD = inputs consumed per PE per cycle      (unrolls the MW loop)
--   => PE*SIMD MACs/cycle, cycles per vector = (MH/PE)*(MW/SIMD)
-- NOTE: VHDL is case-insensitive, so the fold constants are NFOLD/SFOLD and
-- the counters nf/sf (NF and nf would be the same identifier).
-- The weight ROM is built at elaboration from cnn_weights_pkg for the
-- chosen PE/SIMD, so folding is changed with generics only (DSE).
-- Inputs: unsigned IDW bits. Weights: signed 8 bits. Accumulator: ACCW bits.
-- RELU = true : out = clip(acc >> SHIFT, 0, 2^ODW-1)  (truncate + saturate)
-- RELU = false: out = raw signed accumulator (logits)
-- A new input vector is accepted in the same cycle the previous one
-- finishes, so back-to-back vectors take exactly (MH/PE)*(MW/SIMD) cycles.
-- [ISE 14.7] Ported to VHDL-93: explicit sensitivity list, no 2**32 overflow.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cnn_weights_pkg.all;

entity mvau is
  generic (
    LAYER : natural  := 1;             -- which weight set in cnn_weights_pkg
    MW    : positive := 9;  MH   : positive := 8;
    PE    : positive := 8;  SIMD : positive := 9;
    IDW   : positive := 8;  ACCW : positive := 32;
    RELU  : boolean  := true;
    SHIFT : natural  := 0;  ODW  : positive := 8);
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(MW*IDW-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(MH*ODW-1 downto 0));
end entity;

architecture rtl of mvau is
  constant WDW : positive := 8;
  constant NFOLD  : positive := MH / PE;     -- neuron fold
  constant SFOLD  : positive := MW / SIMD;   -- synapse fold

  -- ROM word (nf,sf): lane (pe,s) = W[sf*SIMD+s][nf*PE+pe]
  type rom_t  is array (0 to NFOLD*SFOLD-1) of std_logic_vector(PE*SIMD*WDW-1 downto 0);
  type bias_t is array (0 to MH-1) of signed(ACCW-1 downto 0);
  type acc_t  is array (0 to PE-1) of signed(ACCW-1 downto 0);

  function init_rom return rom_t is
    variable r : rom_t;
    variable lane : natural;
  begin
    for nf in 0 to NFOLD-1 loop
      for sf in 0 to SFOLD-1 loop
        for p in 0 to PE-1 loop
          for s in 0 to SIMD-1 loop
            lane := p*SIMD + s;
            r(nf*SFOLD+sf)((lane+1)*WDW-1 downto lane*WDW) :=
              std_logic_vector(to_signed(wval(LAYER, sf*SIMD+s, nf*PE+p), WDW));
          end loop;
        end loop;
      end loop;
    end loop;
    return r;
  end function;

  function init_bias return bias_t is
    variable b : bias_t;
  begin
    for i in 0 to MH-1 loop b(i) := to_signed(bval(LAYER, i), ACCW); end loop;
    return b;
  end function;

  -- x+1 that wraps at 'top'. Needed because a fold of 1 gives counters a
  -- range of 0 to 0, and synthesis rejects a plain x+1 there even in a
  -- branch that is never taken.
  function wrap_inc(x, top : natural) return natural is
  begin
    if x >= top then return 0; else return x + 1; end if;
  end function;

  -- [ISE] true if any bit above the ODW-bit output range is set, i.e.
  -- v > 2**ODW-1 for a non-negative v. Replaces the original integer
  -- compare, because 2**ODW overflows VHDL integer when ODW = 32.
  function above_range(v : signed) return boolean is
  begin
    for i in ODW to v'length-1 loop
      if v(v'low + i) = '1' then return true; end if;
    end loop;
    return false;
  end function;

  constant ROM  : rom_t  := init_rom;
  constant BIAS : bias_t := init_bias;

  signal x_reg   : std_logic_vector(MW*IDW-1 downto 0) := (others => '0');
  signal busy    : std_logic := '0';
  signal nf      : natural range 0 to NFOLD-1 := 0;
  signal sf      : natural range 0 to SFOLD-1 := 0;
  signal waddr   : natural range 0 to NFOLD*SFOLD-1 := 0;   -- walks the ROM sequentially
  signal waddr_n : natural range 0 to NFOLD*SFOLD-1;        -- address for the NEXT cycle
  signal wword_q : std_logic_vector(PE*SIMD*WDW-1 downto 0) := (others => '0');
  signal acc     : acc_t := (others => (others => '0'));
  signal accn    : acc_t;
  signal stage   : std_logic_vector(MH*ODW-1 downto 0) := (others => '0');
  signal stage_n : std_logic_vector(MH*ODW-1 downto 0);
  signal ov      : std_logic := '0';
  signal last, can_out, step, rdy, in_fire : std_logic;
begin
  last    <= '1' when nf = NFOLD-1 and sf = SFOLD-1 else '0';
  can_out <= (not ov) or out_ready;
  step    <= busy and ((not last) or can_out);
  rdy     <= (not busy) or (last and can_out);
  in_ready  <= rdy;
  in_fire   <= in_valid and rdy;
  out_valid <= ov;

  -- Synchronous ROM read (so synthesis can map the weights to block RAM):
  -- the address of the NEXT cycle is computed combinationally and the word
  -- is registered, so in every cycle wword_q = ROM(waddr) -- exactly the
  -- same timing as an asynchronous read, but BRAM-friendly.
  waddr_n <= 0 when rst = '1' or in_fire = '1' else
             0 when step = '1' and last = '1' else
             wrap_inc(waddr, NFOLD*SFOLD-1) when step = '1' else
             waddr;

  rom_read : process (clk)
  begin
    if rising_edge(clk) then
      wword_q <= ROM(waddr_n);
    end if;
  end process;

  -- datapath: PE parallel dot products of length SIMD + requantization
  datapath : process (wword_q, stage, x_reg, sf, nf, acc)   -- [ISE] was process(all)
    variable wword : std_logic_vector(PE*SIMD*WDW-1 downto 0);
    variable dot, a, shv : signed(ACCW-1 downto 0);
    variable xs  : signed(IDW downto 0);
    variable ws  : signed(WDW-1 downto 0);
    variable st  : std_logic_vector(MH*ODW-1 downto 0);
    variable q   : std_logic_vector(ODW-1 downto 0);
    variable lane, o : natural;
  begin
    wword := wword_q;
    st := stage;
    for p in 0 to PE-1 loop
      dot := (others => '0');
      for s in 0 to SIMD-1 loop
        lane := p*SIMD + s;
        ws := signed(wword((lane+1)*WDW-1 downto lane*WDW));
        xs := signed('0' & x_reg((s+1)*IDW-1 downto s*IDW));   -- input is unsigned
        dot := dot + resize(ws * xs, ACCW);
      end loop;
      if sf = 0 then a := BIAS(nf*PE+p) + dot; else a := acc(p) + dot; end if;
      accn(p) <= a;
      if RELU then
        shv := shift_right(a, SHIFT);                  -- arithmetic shift = floor
        if shv < 0 then
          q := (others => '0');
        elsif above_range(shv) then
          q := (others => '1');
        else
          q := std_logic_vector(shv(ODW-1 downto 0));
        end if;
      else
        q := std_logic_vector(a(ODW-1 downto 0));
      end if;
      o := nf*PE + p;
      st((o+1)*ODW-1 downto o*ODW) := q;
    end loop;
    stage_n <= st;
  end process;

  control : process (clk)
  begin
    if rising_edge(clk) then
      waddr <= waddr_n;
      if rst = '1' then
        busy <= '0'; ov <= '0'; nf <= 0; sf <= 0;
      else
        if ov = '1' and out_ready = '1' then ov <= '0'; end if;
        if step = '1' then
          acc <= accn;
          -- rotate the input vector by SIMD elements: after SFOLD steps it is back
          -- in place for the next neuron fold. Avoids a wide MW:1 multiplexer.
          if SFOLD > 1 then
            x_reg <= x_reg(SIMD*IDW-1 downto 0) & x_reg(MW*IDW-1 downto SIMD*IDW);
          end if;
          if sf = SFOLD-1 then stage <= stage_n; end if;
          if last = '1' then
            out_data <= stage_n;
            ov <= '1';
            busy <= '0'; nf <= 0; sf <= 0;
          else
            if sf = SFOLD-1 then
              sf <= 0; nf <= wrap_inc(nf, NFOLD-1);
            else
              sf <= wrap_inc(sf, SFOLD-1);
            end if;
          end if;
        end if;
        if in_fire = '1' then
          x_reg <= in_data; busy <= '1'; nf <= 0; sf <= 0;
        end if;
      end if;
    end if;
  end process;
end architecture;
