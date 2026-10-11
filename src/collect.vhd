-- Flatten: gathers N consecutive pixel vectors into one N*VW vector.
-- A plain shift register (no address decoder): each beat shifts in at the
-- top, so after N beats vector k sits at [k*VW +: VW] -> element
-- (h*5+w)*16+c == Keras Flatten() order (channels-last).
-- Single buffer only: the dense MVAU latches the vector into its own input
-- register when it starts, so collection of the next image begins at once.
library ieee;
use ieee.std_logic_1164.all;

entity collect is
  generic (N : positive := 25; VW : positive := 128);
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(VW-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(N*VW-1 downto 0));
end entity;

architecture rtl of collect is
  signal sreg : std_logic_vector(N*VW-1 downto 0) := (others => '0');
  signal cnt  : natural range 0 to N-1 := 0;
  signal ov, rdy, in_fire : std_logic;
begin
  rdy       <= (not ov) or out_ready;
  in_ready  <= rdy;
  in_fire   <= in_valid and rdy;
  out_valid <= ov;
  out_data  <= sreg;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= 0; ov <= '0';
      else
        if ov = '1' and out_ready = '1' then ov <= '0'; end if;
        if in_fire = '1' then
          sreg <= in_data & sreg(N*VW-1 downto VW);
          if cnt = N-1 then ov <= '1'; cnt <= 0; else cnt <= cnt + 1; end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
