library ieee;
use ieee.std_logic_1164.all;

entity rot_left_32 is
    generic (
        SHIFT : natural range 1 to 31 := 16
    );
    port (
        din  : in  std_logic_vector(31 downto 0);
        dout : out std_logic_vector(31 downto 0)
    );
end entity rot_left_32;

architecture rtl of rot_left_32 is
begin
    -- Structural hardwired rotation (no logic gates consumed)
    dout <= din(31 - SHIFT downto 0) & din(31 downto 32 - SHIFT);
end architecture rtl;