library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity n_bit_register is
    generic (
        N : positive := 8   -- Default width is 8 bits; override upon instantiation
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;                          -- Active-low asynchronous reset
        load  : in  std_logic;                          -- Clock enable / write enable
        d     : in  std_logic_vector(N - 1 downto 0);   -- Data input
        q     : out std_logic_vector(N - 1 downto 0)    -- Data output
    );
end entity n_bit_register;

architecture rtl of n_bit_register is
begin

    reg_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            q <= (others => '0');
        elsif rising_edge(clk) then
            if load = '1' then
                q <= d;
            end if;
        end if;
    end process reg_proc;

end architecture rtl;
