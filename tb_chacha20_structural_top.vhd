library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_chacha20_structural_top is
end entity tb_chacha20_structural_top;

architecture sim of tb_chacha20_structural_top is

    -- 100 MHz clock setup (10 ns period)
    constant CLK_PERIOD : time := 10 ns;

    -- DUT Signals
    signal clk           : std_logic := '0';
    signal rst_n         : std_logic := '0';
    signal start         : std_logic := '0';
    signal ready         : std_logic;
    signal valid         : std_logic;
    signal sim_done      : boolean   := false;

    signal key_in        : std_logic_vector(255 downto 0) := (others => '0');
    signal nonce_in      : std_logic_vector(95 downto 0)  := (others => '0');
    signal counter_in    : std_logic_vector(31 downto 0)  := (others => '0');
    signal keystream_out : std_logic_vector(511 downto 0);

    -- Expected golden words from RFC 8439 Section 2.3.2 (Little-Endian layout)
    -- Exact RFC 8439 Section 2.3.2 Raw Keystream Words (State + Initial State)
    constant EXP_WORD_0  : std_logic_vector(31 downto 0) := x"f3514f22";
    constant EXP_WORD_1  : std_logic_vector(31 downto 0) := x"e1d91b40";
    constant EXP_WORD_2  : std_logic_vector(31 downto 0) := x"6f27de2f";
    constant EXP_WORD_3  : std_logic_vector(31 downto 0) := x"ed1d63b8";
    constant EXP_WORD_15 : std_logic_vector(31 downto 0) := x"b7417df0";

    -- Metavalue-safe hex printer to avoid NUMERIC_STD warnings on uninitialized lines
    function to_hstring_safe(slv : std_logic_vector(31 downto 0)) return string is
        constant HEX_LUT : string(1 to 16) := "0123456789ABCDEF";
        variable res     : string(1 to 8);
        variable nibble  : std_logic_vector(3 downto 0);
        variable val     : integer;
    begin
        for i in 0 to 7 loop
            nibble := slv(31 - (i * 4) downto 28 - (i * 4));
            if is_x(nibble) then
                res(i + 1) := 'X';
            else
                val := to_integer(unsigned(nibble));
                res(i + 1) := HEX_LUT(val + 1);
            end if;
        end loop;
        return res;
    end function to_hstring_safe;

begin

    -- Device Under Test
    dut: entity work.chacha20_structural_top
        port map (
            clk           => clk,
            rst_n         => rst_n,
            start         => start,
            ready         => ready,
            valid         => valid,
            key_in        => key_in,
            nonce_in      => nonce_in,
            counter_in    => counter_in,
            keystream_out => keystream_out
        );

    -- Clock Generation
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_process;

    -- Stimulus and Timing Verification
    stim_proc: process
        variable cycle_counter : integer := 0;
        variable start_time    : time;
        variable w0, w1, w2, w3, w15 : std_logic_vector(31 downto 0);
    begin
        -------------------------------------------------------------------------
        -- 1. Apply Valid Inputs During Reset (Ensures Setup Times Are Met)
        -------------------------------------------------------------------------
        rst_n      <= '0';
        start      <= '0';
        key_in     <= x"1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100";
        nonce_in   <= x"000000004a00000000000000";
        counter_in <= x"00000001";
        wait for 30 ns;

        -- Release reset on falling edge
        wait until falling_edge(clk);
        rst_n <= '1';

        -- Wait for IDLE state to settle
        wait until rising_edge(clk);
        wait for 1 ns;
        assert (ready = '1')
            report "Error: Core did not assert ready = '1' after reset."
            severity error;

        -------------------------------------------------------------------------
        -- 2. Trigger Keystream Generation
        -- Pulse start for 1 cycle aligned with clock
        -------------------------------------------------------------------------
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        start_time := now;

        -------------------------------------------------------------------------
        -- 3. Cycle-Accurate Wait Until Valid Asserts
        -------------------------------------------------------------------------
        while (valid = '0') loop
            wait until rising_edge(clk);
            cycle_counter := cycle_counter + 1;

            if cycle_counter > 50 then
                report "Watchdog timeout! FSM hung before valid asserted." severity failure;
            end if;
        end loop;

        report "Keystream generated in " & integer'image(cycle_counter) & 
               " clock cycles (" & time'image(now - start_time) & ")." severity note;

        -- Settle combinational feed-forward adder network
        wait for 1 ns;

        -------------------------------------------------------------------------
        -- 4. Golden Vector Comparison (RFC 8439 Section 2.3.2)
        -------------------------------------------------------------------------
        w0  := keystream_out(31 downto 0);
        w1  := keystream_out(63 downto 32);
        w2  := keystream_out(95 downto 64);
        w3  := keystream_out(127 downto 96);
        w15 := keystream_out(511 downto 480);

        report "Extracted Word 0  : 0x" & to_hstring_safe(w0);
        report "Extracted Word 1  : 0x" & to_hstring_safe(w1);
        report "Extracted Word 2  : 0x" & to_hstring_safe(w2);
        report "Extracted Word 3  : 0x" & to_hstring_safe(w3);
        report "Extracted Word 15 : 0x" & to_hstring_safe(w15);

        assert (w0 = EXP_WORD_0)
            report "Word 0 Mismatch! Expected 0x" & to_hstring_safe(EXP_WORD_0) & 
                   ", got 0x" & to_hstring_safe(w0) severity error;

        assert (w1 = EXP_WORD_1)
            report "Word 1 Mismatch! Expected 0x" & to_hstring_safe(EXP_WORD_1) & 
                   ", got 0x" & to_hstring_safe(w1) severity error;

        assert (w2 = EXP_WORD_2)
            report "Word 2 Mismatch! Expected 0x" & to_hstring_safe(EXP_WORD_2) & 
                   ", got 0x" & to_hstring_safe(w2) severity error;

        assert (w3 = EXP_WORD_3)
            report "Word 3 Mismatch! Expected 0x" & to_hstring_safe(EXP_WORD_3) & 
                   ", got 0x" & to_hstring_safe(w3) severity error;

        assert (w15 = EXP_WORD_15)
            report "Word 15 Mismatch! Expected 0x" & to_hstring_safe(EXP_WORD_15) & 
                   ", got 0x" & to_hstring_safe(w15) severity error;

        if (w0 = EXP_WORD_0 and w1 = EXP_WORD_1 and w2 = EXP_WORD_2 and 
            w3 = EXP_WORD_3 and w15 = EXP_WORD_15) then
            report "=== RFC 8439 VERIFICATION PASSED ===" severity note;
        end if;

        -- Check return to ready state
        wait until rising_edge(clk);
        wait for 1 ns;
        assert (ready = '1')
            report "Error: Core did not return to ready after block completion."
            severity error;

        wait for CLK_PERIOD * 3;
        sim_done <= true;
        wait;
    end process stim_proc;

end architecture sim;