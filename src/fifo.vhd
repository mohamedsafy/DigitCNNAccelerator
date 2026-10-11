-- Simple synchronous FIFO (valid/ready on both sides). Decouples pipeline
-- stages so a fast producer can run ahead while a slow consumer is busy --
-- FINN inserts and sizes these automatically (step "set_fifo_depths").
library ieee;
use ieee.std_logic_1164.all;

entity fifo is
  generic (DW : positive := 64; DEPTH : positive := 32);
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(DW-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(DW-1 downto 0));
end entity;

architecture rtl of fifo is
  type mem_t is array (0 to DEPTH-1) of std_logic_vector(DW-1 downto 0);
  signal mem    : mem_t := (others => (others => '0'));
  signal cnt    : natural range 0 to DEPTH := 0;
  signal rp, wp : natural range 0 to DEPTH-1 := 0;
  signal wr, rd, full, empty : std_logic;
begin
  full      <= '1' when cnt = DEPTH else '0';
  empty     <= '1' when cnt = 0 else '0';
  in_ready  <= not full;
  out_valid <= not empty;
  out_data  <= mem(rp);
  wr <= in_valid and not full;
  rd <= out_ready and not empty;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= 0; rp <= 0; wp <= 0;
      else
        if wr = '1' then
          mem(wp) <= in_data;
          if wp = DEPTH-1 then wp <= 0; else wp <= wp + 1; end if;
        end if;
        if rd = '1' then
          if rp = DEPTH-1 then rp <= 0; else rp <= rp + 1; end if;
        end if;
        if wr = '1' and rd = '0' then cnt <= cnt + 1;
        elsif wr = '0' and rd = '1' then cnt <= cnt - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
