library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity switch is
    port( x : in STD_LOGIC_VECTOR(1 downto 0);
          sel : in STD_LOGIC;
          y : out STD_LOGIC_VECTOR(1 downto 0)
    );
end entity switch;

architecture rtl of switch is

begin
    y(0) <= (x(0) and not(sel)) or (x(1) and sel);
    y(1) <= (x(1) and not(sel)) or (x(0) and sel);

end architecture rtl;