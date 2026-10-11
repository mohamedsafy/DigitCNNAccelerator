-- Combinational argmax over N signed logits (first index wins on ties,
-- same as numpy.argmax). Softmax is not needed for classification.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity argmax is
  generic (N : positive := 10; DW : positive := 32);
  port (
    in_data : in  std_logic_vector(N*DW-1 downto 0);
    idx     : out std_logic_vector(3 downto 0));
end entity;

architecture rtl of argmax is
begin
  process (in_data)   -- [ISE] was process(all)
    variable best : signed(DW-1 downto 0);
    variable bi   : natural range 0 to N-1;
  begin
    best := signed(in_data(DW-1 downto 0));
    bi := 0;
    for i in 1 to N-1 loop
      if signed(in_data((i+1)*DW-1 downto i*DW)) > best then
        best := signed(in_data((i+1)*DW-1 downto i*DW));
        bi := i;
      end if;
    end loop;
    idx <= std_logic_vector(to_unsigned(bi, 4));
  end process;
end architecture;
