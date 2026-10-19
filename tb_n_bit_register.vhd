library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_n_bit_register is
    -- Testbench top-level entity has no external ports
end entity tb_n_bit_register;

architecture sim of tb_n_bit_register is

    -- Constant to configure the register width for testing
    constant TEST_WIDTH : positive := 8;
    constant CLK_PERIOD : time := 10 ns;

    -- Device Under Test (DUT) component declaration
    component n_bit_register is
        generic (
            N : positive := 8
        );
        port (
            clk   : in  std_logic;
            rst_n : in  std_logic;
            load  : in  std_logic;
            d     : in  std_logic_vector(N - 1 downto 0);
            q     : out std_logic_vector(N - 1 downto 0)
        );
    end component n_bit_register;

    -- Stimulus and observation signals
    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal load  : std_logic := '0';
    signal d     : std_logic_vector(TEST_WIDTH - 1 downto 0) := (others => '0');
    signal q     : std_logic_vector(TEST_WIDTH - 1 downto 0);

begin

    -- Instantiate the DUT with overridden generic parameter
    dut: n_bit_register
        generic map (
            N => TEST_WIDTH
        )
        port map (
            clk   => clk,
            rst_n => rst_n,
            load  => load,
            d     => d,
            q     => q
        );

    -- Clock generation process: 100 MHz (10 ns period)
    clk_process: process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process clk_process;

    -- Stimulus process
    stim_proc: process
    begin
        -- ==============================================================
        -- Test Case 1: Asynchronous Reset Assertion
        -- ==============================================================
        rst_n <= '0';
        load  <= '0';
        d     <= x"AA";
        wait for 15 ns;

        assert (q = x"00")
            report "Test 1 Failed: Asynchronous reset did not clear q"
            severity error;

        -- Release reset synchronously with clock falling edge
        wait until falling_edge(clk);
        rst_n <= '1';
        wait for CLK_PERIOD;

        -- ==============================================================
        -- Test Case 2: Load Enable Active (q should latch d)
        -- ==============================================================
        d    <= x"A5";
        load <= '1';
        wait until rising_edge(clk);
        wait for 1 ns; -- Delta delay to verify settled state

        assert (q = x"A5")
            report "Test 2 Failed: Register failed to load new value when load = '1'"
            severity error;

        -- Load a second pattern
        d <= x"3C";
        wait until rising_edge(clk);
        wait for 1 ns;

        assert (q = x"3C")
            report "Test 2b Failed: Register failed to load second pattern when load = '1'"
            severity error;

        -- ==============================================================
        -- Test Case 3: Load Disabled / Hold Mode (q must retain value)
        -- ==============================================================
        load <= '0';
        d    <= x"FF"; -- Change d while load is de-asserted
        wait until rising_edge(clk);
        wait for 1 ns;

        assert (q = x"3C")
            report "Test 3 Failed: Register modified output when load = '0'"
            severity error;

        -- Verify retention across multiple clock cycles
        wait for 3 * CLK_PERIOD;
        assert (q = x"3C")
            report "Test 3b Failed: Register failed to maintain held value over idle cycles"
            severity error;

        -- ==============================================================
        -- Test Case 4: Asynchronous Reset Overrides Load
        -- ==============================================================
        load  <= '1';
        d     <= x"5A";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert (q = x"5A")
            report "Setup Failed: Value not latched prior to async reset test"
            severity error;

        -- Assert reset mid-cycle (asynchronous to clock)
        wait for 3 ns;
        rst_n <= '0';
        wait for 1 ns;

        assert (q = x"00")
            report "Test 4 Failed: Asynchronous reset did not clear output immediately"
            severity error;

        -- Clean deassertion and test completion
        wait until falling_edge(clk);
        rst_n <= '1';
        load  <= '0';
        wait for CLK_PERIOD;

        report "All register tests completed successfully." severity note;
        wait;
    end process stim_proc;

end architecture sim;