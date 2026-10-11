-- ============================================================================
-- Sliding Window Generator (3x3, stride 1, no padding) -- script section 4,
-- "Line buffer": keeps the last K-1 = 2 rows in line buffers plus a 3x3
-- window register. Buffer size = (K-1)*W*C elements.
-- One pixel vector (all C channels) per input beat; one 3x3xC window per
-- output beat. Window element order (LSB first): idx = (ki*3 + kj)*C + c,
-- which equals Keras kernel.reshape(K*K*C, M) order and the golden im2col.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity swg3x3 is
  generic (W : positive := 28; H : positive := 28; C : positive := 1; DW : positive := 8);
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(C*DW-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(9*C*DW-1 downto 0));
end entity;

architecture rtl of swg3x3 is
  constant PW : positive := C*DW;
  subtype pix_t is std_logic_vector(PW-1 downto 0);
  type lb_t  is array (0 to W-1) of pix_t;
  type win_t is array (0 to 8) of pix_t;
  signal lb0 : lb_t  := (others => (others => '0'));   -- row r-2 (oldest)
  signal lb1 : lb_t  := (others => (others => '0'));   -- row r-1
  signal win : win_t := (others => (others => '0'));   -- win(ki*3+kj)
  signal col : natural range 0 to W-1 := 0;
  signal row : natural range 0 to H-1 := 0;
  signal ov, rdy, in_fire : std_logic;
begin
  rdy       <= (not ov) or out_ready;
  in_ready  <= rdy;
  in_fire   <= in_valid and rdy;
  out_valid <= ov;
  pack : for g in 0 to 8 generate
    out_data((g+1)*PW-1 downto g*PW) <= win(g);
  end generate;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ov <= '0'; col <= 0; row <= 0;
      else
        if ov = '1' and out_ready = '1' then ov <= '0'; end if;
        if in_fire = '1' then
          -- shift the window left, insert the new column {lb0(col), lb1(col), pixel}
          win(0) <= win(1); win(1) <= win(2); win(2) <= lb0(col);
          win(3) <= win(4); win(4) <= win(5); win(5) <= lb1(col);
          win(6) <= win(7); win(7) <= win(8); win(8) <= in_data;
          lb0(col) <= lb1(col);
          lb1(col) <= in_data;
          if row >= 2 and col >= 2 then ov <= '1'; else ov <= '0'; end if;
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
