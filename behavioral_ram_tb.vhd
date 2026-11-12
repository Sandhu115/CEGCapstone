library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity behavioral_ram_tb is
end entity behavioral_ram_tb;

architecture sim of behavioral_ram_tb is

    -- Match default generics of behavioral_ram
    constant ROW_ADDR_W  : integer := 8;
    constant BLK_IDX_W   : integer := 4;
    constant ADDR_W      : integer := ROW_ADDR_W + BLK_IDX_W; -- 12 bits (4096 blocks)
    constant DATA_W      : integer := 512;
    constant INIT_TAGGED : boolean := true;
    constant CLK_PERIOD  : time    := 10 ns;

    -- DUT Signals
    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal ram_en     : std_logic := '0';
    signal ram_we     : std_logic := '0';
    signal ram_addr   : std_logic_vector(ADDR_W - 1 downto 0) := (others => '0');
    signal ram_wdata  : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
    signal ram_rdata  : std_logic_vector(DATA_W - 1 downto 0);
    signal ram_rvalid : std_logic;

    -- Simulation control flag
    signal sim_done   : boolean := false;

begin

    -- Instantiate Unit Under Test (UUT)
    uut : entity work.behavioral_ram
        generic map (
            ROW_ADDR_W  => ROW_ADDR_W,
            BLK_IDX_W   => BLK_IDX_W,
            DATA_W      => DATA_W,
            INIT_TAGGED => INIT_TAGGED
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            ram_en     => ram_en,
            ram_we     => ram_we,
            ram_addr   => ram_addr,
            ram_wdata  => ram_wdata,
            ram_rdata  => ram_rdata,
            ram_rvalid => ram_rvalid
        );

    -- Clock Generation
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus & Self-Checking Process
    stim_proc : process
        variable expected_data : std_logic_vector(DATA_W - 1 downto 0);
        variable test_pattern  : std_logic_vector(DATA_W - 1 downto 0);
    begin
        ------------------------------------------------------------------------
        -- TEST 1: Reset & Tagged Initialization Check
        ------------------------------------------------------------------------
        rst_n  <= '0';
        ram_en <= '0';
        ram_we <= '0';
        wait for CLK_PERIOD * 2;
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        -- Read Row 0x2A, Block 0x5 (Address = 0x2A5)
        ram_en   <= '1';
        ram_we   <= '0';
        ram_addr <= x"2A5";
        wait until rising_edge(clk);
        ram_en   <= '0';
        wait for 1 ns; -- Allow delta cycles to settle after clock edge

        expected_data := std_logic_vector(to_unsigned(16#2A5#, DATA_W));
        assert ram_rvalid = '1'
            report "FAIL [Test 1]: ram_rvalid did not assert 1 cycle after read request."
            severity failure;
        assert ram_rdata = expected_data
            report "FAIL [Test 1]: Tagged initial data mismatch at 0x2A5."
            severity failure;

        -- Verify ram_rvalid de-asserts on the following cycle
        wait until rising_edge(clk);
        wait for 1 ns;
        assert ram_rvalid = '0'
            report "FAIL [Test 1]: ram_rvalid failed to de-assert after single-cycle read."
            severity failure;

        ------------------------------------------------------------------------
        -- TEST 2: Synchronous Write & Readback Verification
        ------------------------------------------------------------------------
        -- Build a distinct 512-bit test pattern (repeating 0xDEADBEEFCAFEBABE)
        for k in 0 to (DATA_W / 64) - 1 loop
            test_pattern((k * 64) + 63 downto k * 64) := x"DEADBEEFCAFEBABE";
        end loop;

        ram_en    <= '1';
        ram_we    <= '1';
        ram_addr  <= x"042";
        ram_wdata <= test_pattern;
        wait until rising_edge(clk);
        ram_en    <= '0';
        ram_we    <= '0';
        wait for 1 ns;

        assert ram_rvalid = '0'
            report "FAIL [Test 2]: ram_rvalid should not assert during a write cycle."
            severity failure;

        -- Read back address 0x042
        wait until rising_edge(clk);
        ram_en   <= '1';
        ram_we   <= '0';
        ram_addr <= x"042";
        wait until rising_edge(clk);
        ram_en   <= '0';
        wait for 1 ns;

        assert (ram_rvalid = '1') and (ram_rdata = test_pattern)
            report "FAIL [Test 2]: Readback data did not match written pattern at 0x042."
            severity failure;

        ------------------------------------------------------------------------
        -- TEST 3: Churn Zero-Erase Simulation
        ------------------------------------------------------------------------
        wait until rising_edge(clk);
        ram_en    <= '1';
        ram_we    <= '1';
        ram_addr  <= x"042";
        ram_wdata <= (others => '0');
        wait until rising_edge(clk);
        ram_en    <= '0';
        ram_we    <= '0';

        -- Read back address 0x042 to confirm zero-erase
        wait until rising_edge(clk);
        ram_en   <= '1';
        ram_we   <= '0';
        ram_addr <= x"042";
        wait until rising_edge(clk);
        ram_en   <= '0';
        wait for 1 ns;

        expected_data := (others => '0');
        assert (ram_rvalid = '1') and (ram_rdata = expected_data)
            report "FAIL [Test 3]: Block at 0x042 was not properly zero-erased."
            severity failure;

        ------------------------------------------------------------------------
        -- TEST 4: Write Protection When ram_en = '0'
        ------------------------------------------------------------------------
        wait until rising_edge(clk);
        ram_en    <= '0';
        ram_we    <= '1'; -- Attempt write with enable low
        ram_addr  <= x"010";
        ram_wdata <= (others => '1');
        wait until rising_edge(clk);
        ram_we    <= '0';

        -- Read address 0x010 to verify original tagged value (0x010) was untouched
        ram_en   <= '1';
        ram_we   <= '0';
        ram_addr <= x"010";
        wait until rising_edge(clk);
        ram_en   <= '0';
        wait for 1 ns;

        expected_data := std_logic_vector(to_unsigned(16#010#, DATA_W));
        assert (ram_rvalid = '1') and (ram_rdata = expected_data)
            report "FAIL [Test 4]: Memory was overwritten while ram_en was '0'."
            severity failure;

        ------------------------------------------------------------------------
        -- TEST 5: Back-to-Back Pipelined Reads
        ------------------------------------------------------------------------
        wait until rising_edge(clk);
        ram_en   <= '1';
        ram_we   <= '0';
        ram_addr <= x"100";
        wait until rising_edge(clk);
        -- Immediately issue second read address on next cycle
        ram_addr <= x"101";
        wait for 1 ns;

        expected_data := std_logic_vector(to_unsigned(16#100#, DATA_W));
        assert (ram_rvalid = '1') and (ram_rdata = expected_data)
            report "FAIL [Test 5]: First back-to-back read (0x100) failed."
            severity failure;

        wait until rising_edge(clk);
        ram_en <= '0';
        wait for 1 ns;

        expected_data := std_logic_vector(to_unsigned(16#101#, DATA_W));
        assert (ram_rvalid = '1') and (ram_rdata = expected_data)
            report "FAIL [Test 5]: Second back-to-back read (0x101) failed."
            severity failure;

        ------------------------------------------------------------------------
        -- ALL TESTS PASSED
        ------------------------------------------------------------------------
        wait for CLK_PERIOD * 2;
        report "SUCCESS: All behavioral_ram tests passed!" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;