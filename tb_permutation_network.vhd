library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_permutation_network is
end entity tb_permutation_network;

architecture behavioral of tb_permutation_network is

    -- Component Declaration for the Unit Under Test (UUT)
    component permutation_network
        port(
            logical_address  : in  STD_LOGIC_VECTOR(31 downto 0);
            clk              : in  STD_LOGIC;
            rst              : in  STD_LOGIC;
            churn            : in  STD_LOGIC;
            physical_address : out STD_LOGIC_VECTOR(31 downto 0)
        );
    end component;

    -- Inputs
    signal clk             : STD_LOGIC := '0';
    signal rst             : STD_LOGIC := '0';
    signal churn           : STD_LOGIC := '0';
    signal logical_address : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- Outputs
    signal physical_address : STD_LOGIC_VECTOR(31 downto 0);

    -- Clock period definition
    constant CLK_PERIOD : time := 10 ns;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: permutation_network
        port map (
            logical_address  => logical_address,
            clk              => clk,
            rst              => rst,
            churn            => churn,
            physical_address => physical_address
        );

    -- Clock generation process
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Stimulus process
    stim_process : process
    begin
        -- Step 1: Initialize inputs and assert active-low reset (rst = '0')
        rst <= '0';
        churn <= '0';
        logical_address <= x"00000000";
        wait for 20 ns;
        
        -- Step 2: Release reset (rst = '1')
        rst <= '1';
        wait for 20 ns;

        -- Step 3: Apply first test logical address
        logical_address <= x"12345678";
        wait for 40 ns;

        -- Step 4: Trigger churn to request a new random key from the TRNG model
        churn <= '1';
        wait for CLK_PERIOD;
        churn <= '0';
        wait for 40 ns;

        -- Step 5: Test with a new logical address while key remains stable
        logical_address <= x"DEADBEEF";
        wait for 40 ns;

        -- Step 6: Trigger churn again with another address change
        logical_address <= x"CAFE0001";
        churn <= '1';
        wait for CLK_PERIOD;
        churn <= '0';
        wait for 50 ns;

        -- End simulation
        report "Simulation completed successfully." severity note;
        wait;
    end process;

end architecture behavioral;