-- ============================================================================
-- Streaming 2x2 / stride-2 max pooling on a raster pixel stream (C lanes,
-- unsigned). Needs only a buffer of W/2 pixel vectors. Rows/cols that do not
-- fill a whole 2x2 window (e.g. the last row/col of 11x11) are dropped,
-- exactly like Keras MaxPooling2D(padding='valid').
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool2x2 is
  generic (W : positive := 26; H : positive := 26; C : positive := 8; DW : positive := 8);
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(C*DW-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(C*DW-1 downto 0));
end entity;

architecture rtl of maxpool2x2 is
  constant WO : positive := W/2;
  constant HO : positive := H/2;
  subtype pix_t is std_logic_vector(C*DW-1 downto 0);
  type rbuf_t is array (0 to WO-1) of pix_t;
  signal rbuf : rbuf_t := (others => (others => '0'));
  signal tmp  : pix_t := (others => '0');
  signal col  : natural range 0 to W-1 := 0;
  signal row  : natural range 0 to H-1 := 0;
  signal ov, rdy, in_fire : std_logic;

  function vmax(a, b : pix_t) return pix_t is
    variable r : pix_t;
  begin
    for i in 0 to C-1 loop
      if unsigned(a((i+1)*DW-1 downto i*DW)) > unsigned(b((i+1)*DW-1 downto i*DW)) then
        r((i+1)*DW-1 downto i*DW) := a((i+1)*DW-1 downto i*DW);
      else
        r((i+1)*DW-1 downto i*DW) := b((i+1)*DW-1 downto i*DW);
      end if;
    end loop;
    return r;
  end function;
begin
  rdy       <= (not ov) or out_ready;
  in_ready  <= rdy;
  in_fire   <= in_valid and rdy;
  out_valid <= ov;

  process (clk)
    variable pc : natural range 0 to W-1;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ov <= '0'; col <= 0; row <= 0;
      else
        if ov = '1' and out_ready = '1' then ov <= '0'; end if;
        if in_fire = '1' then
          if row < 2*HO and col < 2*WO then
            pc := col / 2;
            if row mod 2 = 0 and col mod 2 = 0 then
              tmp <= in_data;
            elsif row mod 2 = 0 then
              rbuf(pc) <= vmax(tmp, in_data);
            elsif col mod 2 = 0 then
              tmp <= vmax(rbuf(pc), in_data);
            else
              out_data <= vmax(tmp, in_data);
              ov <= '1';
            end if;
          end if;
          if col = W-1 then
            col <= 0;
            if row = H-1 then row <= 0; else row <= row + 1; end if;
          else
            col <= col + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
