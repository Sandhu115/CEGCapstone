library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mux2to1_nbit is
    generic (
        N : positive := 8  -- Default bus width is 8 bits
    );
    port (
        d0  : in  std_logic_vector(N - 1 downto 0);
        d1  : in  std_logic_vector(N - 1 downto 0);
        sel : in  std_logic;
        y   : out std_logic_vector(N - 1 downto 0)
    );
end entity mux2to1_nbit;

-- Architecture 1: Dataflow (Conditional Signal Assignment)
architecture dataflow of mux2to1_nbit is
begin
    y <= d1 when sel = '1' else d0;
end architecture dataflow;

-- Architecture 2: Behavioral (Process with CASE statement)
-- architecture behavioral of mux2to1_nbit is
-- begin
--     process(sel, d0, d1)
--     begin
--         case sel is
--             when '1' =>
--                 y <= d1;
--             when others =>
--                 y <= d0;
--         end case;
--     end process;
-- end architecture behavioral;