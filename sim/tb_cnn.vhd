-- Testbench: streams N test images back-to-back (1 pixel per cycle when
-- accepted), checks every predicted class against the bit-exact Python
-- golden model and the true label, and measures latency and throughput.
-- [ISE 14.7] VHDL-93 version for ISim. The files images.txt, golden_pred.txt
-- and labels.txt must be in the ISim working directory (the project folder).
-- Run with "run all": the clock stops by itself when all images are checked.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_cnn is
  generic (
    N : positive := 20;          -- must match the vectors in images.txt
    PE1 : positive := 8;  SIMD1 : positive := 9;
    PE2 : positive := 16; SIMD2 : positive := 8;
    PE3 : positive := 1;  SIMD3 : positive := 4;
    FIFO_DEPTH : natural := 32);
end entity;

architecture sim of tb_cnn is
  type img_t is array (0 to N*784-1) of std_logic_vector(7 downto 0);
  type int_t is array (0 to N-1) of integer;

  -- [ISE] images are stored as decimal (0..255) and read with plain
  -- std.textio, so no std_logic_textio / hread is needed.
  impure function load_images return img_t is
    file f : text open read_mode is "images.txt";
    variable l : line; variable v : integer; variable r : img_t;
  begin
    for i in r'range loop
      readline(f, l); read(l, v); r(i) := std_logic_vector(to_unsigned(v, 8));
    end loop;
    return r;
  end function;

  impure function load_ints(fname : string) return int_t is
    file f : text open read_mode is fname;
    variable l : line; variable v : integer; variable r : int_t;
  begin
    for i in r'range loop readline(f, l); read(l, v); r(i) := v; end loop;
    return r;
  end function;

  constant IMG  : img_t := load_images;
  constant GOLD : int_t := load_ints("golden_pred.txt");
  constant LAB  : int_t := load_ints("labels.txt");

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal in_valid : std_logic;
  signal sent_all : boolean := false;
  signal in_ready, out_valid : std_logic;
  signal out_class : std_logic_vector(3 downto 0);
  signal pix : natural := 0;
  signal in_pixel : std_logic_vector(7 downto 0);   -- [ISE] VHDL-93: port actual must be a signal
  signal done : boolean := false;
begin
  clk <= not clk after 5 ns when not done;     -- 100 MHz reference clock

  dut : entity work.cnn_top
    generic map (PE1, SIMD1, PE2, SIMD2, PE3, SIMD3, FIFO_DEPTH)
    port map (clk, rst, in_valid, in_ready, in_pixel, out_valid, '1', out_class);

  in_pixel <= IMG(pix);

  -- NOTE: in_valid is driven from ONE place only. (In VHDL two processes
  -- assigning the same std_logic create two drivers -> resolved to 'X'.)
  in_valid <= '1' when rst = '0' and not sent_all else '0';

  stim : process
  begin
    for i in 1 to 4 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    wait;
  end process;

  check : process (clk)
    variable cyc, nout, gold_ok, lab_ok : natural := 0;
    variable t_first_in, t_first_out, t_last_out : integer := -1;
    variable cls : natural;
    variable l : line;
  begin
    if rising_edge(clk) then
      cyc := cyc + 1;
      if rst = '0' then
        if in_valid = '1' and in_ready = '1' then
          if t_first_in < 0 then t_first_in := cyc; end if;
          if pix = N*784-1 then sent_all <= true; else pix <= pix + 1; end if;
        end if;
        if out_valid = '1' and not done then
          cls := to_integer(unsigned(out_class));
          if cls = GOLD(nout) then gold_ok := gold_ok + 1;
          else
            write(l, string'("MISMATCH img ") & integer'image(nout) & " rtl=" & integer'image(cls)
                     & " golden=" & integer'image(GOLD(nout)));
            writeline(output, l);
          end if;
          if cls = LAB(nout) then lab_ok := lab_ok + 1; end if;
          if nout = 0 then t_first_out := cyc; end if;
          t_last_out := cyc;
          nout := nout + 1;
          if nout = N then
            write(l, string'("images           : ") & integer'image(N)); writeline(output, l);
            write(l, string'("RTL == golden    : ") & integer'image(gold_ok) & " / " & integer'image(N)
                     & " (bit-exact check)"); writeline(output, l);
            write(l, string'("RTL accuracy     : ") & integer'image(lab_ok * 10000 / N / 100) & "."
                     & integer'image((lab_ok * 10000 / N) mod 100 / 10) & integer'image((lab_ok * 10000 / N) mod 10)
                     & " %"); writeline(output, l);
            write(l, string'("latency (img 0)  : ") & integer'image(t_first_out - t_first_in)
                     & " cycles (first pixel in -> class out)"); writeline(output, l);
            if N > 1 then
              write(l, string'("throughput       : ") & integer'image((t_last_out - t_first_out) / (N-1)) & "."
                       & integer'image(((t_last_out - t_first_out) * 10 / (N-1)) mod 10)
                       & " cycles/image (steady state, avg over last " & integer'image(N-1) & ")");
              writeline(output, l);
            end if;
            done <= true;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
