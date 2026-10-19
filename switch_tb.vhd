library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity switch_tb is
    -- A testbench top-level entity has no ports
end entity switch_tb;

architecture sim of switch_tb is

    -- Component declaration for Device Under Test (DUT)
    component switch is
        port (
            x   : in  std_logic_vector(1 downto 0);
            sel : in  std_logic;
            y   : out std_logic_vector(1 downto 0)
        );
    end component switch;

    -- Testbench internal signals to drive and observe the DUT
    signal tb_x   : std_logic_vector(1 downto 0) := "00";
    signal tb_sel : std_logic := '0';
    signal tb_y   : std_logic_vector(1 downto 0);

begin

    -- Instantiate the Device Under Test (DUT)
    dut: switch
        port map (
            x   => tb_x,
            sel => tb_sel,
            y   => tb_y
        );

    -- Stimulus process
    stim_proc: process
    begin
        -- ==============================================================
        -- Test Case 1: Pass-through mode (sel = '0') -> y should equal x
        -- ==============================================================
        tb_sel <= '0';

        tb_x <= "00";
        wait for 10 ns;
        assert (tb_y = "00")
            report "Test failed: sel=0, x=00 -> expected y=00, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "01";
        wait for 10 ns;
        assert (tb_y = "01")
            report "Test failed: sel=0, x=01 -> expected y=01, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "10";
        wait for 10 ns;
        assert (tb_y = "10")
            report "Test failed: sel=0, x=10 -> expected y=10, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "11";
        wait for 10 ns;
        assert (tb_y = "11")
            report "Test failed: sel=0, x=11 -> expected y=11, got " & to_bstring(tb_y)
            severity error;

        -- ==============================================================
        -- Test Case 2: Swap mode (sel = '1') -> y bits should be inverted/swapped
        -- y(0) <= x(1), y(1) <= x(0)
        -- ==============================================================
        tb_sel <= '1';

        tb_x <= "00";
        wait for 10 ns;
        assert (tb_y = "00")
            report "Test failed: sel=1, x=00 -> expected y=00, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "01"; -- x(1)='0', x(0)='1' -> expected y(1)='1', y(0)='0' ("10")
        wait for 10 ns;
        assert (tb_y = "10")
            report "Test failed: sel=1, x=01 -> expected y=10, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "10"; -- x(1)='1', x(0)='0' -> expected y(1)='0', y(0)='1' ("01")
        wait for 10 ns;
        assert (tb_y = "01")
            report "Test failed: sel=1, x=10 -> expected y=01, got " & to_bstring(tb_y)
            severity error;

        tb_x <= "11";
        wait for 10 ns;
        assert (tb_y = "11")
            report "Test failed: sel=1, x=11 -> expected y=11, got " & to_bstring(tb_y)
            severity error;

        -- Finish simulation
        report "All tests completed successfully!" severity note;
        wait; -- Halts the process indefinitely
    end process;

end architecture sim;
