library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_double_permutation_network is
end entity tb_double_permutation_network;

architecture sim of tb_double_permutation_network is

    -- Constant definitions
    constant CLK_PERIOD : time := 10 ns;
    constant TEST_SPACE : natural := 65536; -- Full 16-bit permutation domain (2^16)

    -- DUT signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '0';
    signal churn            : std_logic := '0';
    signal reversal         : std_logic := '0';
    signal logical_address  : std_logic_vector(31 downto 0) := (others => '0');
    signal physical_address : std_logic_vector(31 downto 0);

    -- Simulation control
    signal sim_done : boolean := false;

    -- DUT Component declaration
    component double_permutation_network
        port(
            logical_address  : in  std_logic_vector(31 downto 0);
            clk, rst, churn  : in  std_logic;
            reversal         : in  std_logic;
            physical_address : out std_logic_vector(31 downto 0)
        );
    end component double_permutation_network;

begin

    -- -------------------------------------------------------------
    -- DUT Instantiation
    -- -------------------------------------------------------------
    dut : double_permutation_network
        port map(
            logical_address  => logical_address,
            clk              => clk,
            rst              => rst,
            churn            => churn,
            reversal         => reversal,
            physical_address => physical_address
        );

    -- -------------------------------------------------------------
    -- Clock Generation
    -- -------------------------------------------------------------
    clk_process : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_process;

    -- -------------------------------------------------------------
    -- Main Verification Process
    -- -------------------------------------------------------------
    stim_proc : process
        -- Tracking array for collision detection (Injective / One-to-One mapping check)
        type seen_map_t is array (0 to TEST_SPACE - 1) of boolean;
        variable seen_phys_addr : seen_map_t;

        -- Array to record the permutation function for determinism / stability check
        type mapping_history_t is array (0 to TEST_SPACE - 1) of std_logic_vector(15 downto 0);
        variable baseline_map : mapping_history_t;

        variable curr_phys_slice : std_logic_vector(15 downto 0);
        variable phys_int        : integer range 0 to TEST_SPACE - 1;
        variable duplicate_found : boolean;
        variable is_different    : boolean;

        variable orig_log_addr   : std_logic_vector(31 downto 0);
        variable fwd_phys_addr   : std_logic_vector(31 downto 0);
        variable recovered_addr  : std_logic_vector(31 downto 0);

        -- Procedure to pulse churn for exactly one clock cycle
        procedure pulse_churn is
        begin
            @(posedge clk);
            churn <= '1';
            @(posedge clk);
            churn <= '0';
            @(posedge clk);
        end procedure;

    begin
        -- ---------------------------------------------------------
        -- Initialization and Reset Sequence
        -- ---------------------------------------------------------
        report "[TESTBENCH] Starting Double Permutation Network Verification...";
        rst             <= '0';
        churn           <= '0';
        reversal        <= '0';
        logical_address <= (others => '0');

        wait for CLK_PERIOD * 3;
        @(negedge clk);
        rst <= '1'; -- Deassert reset (active-low)
        wait for CLK_PERIOD * 2;

        -- Initial churn pulse to seed registers with the first key
        report "[TESTBENCH] Generating Initial Key (Epoch 0)...";
        pulse_churn;

        -- =========================================================
        -- TEST CASE 1 & 2: Bijective Check (One-to-One & No Collisions)
        -- =========================================================
        report "[TESTBENCH] Running Test Case 1 & 2: Testing all 65,536 inputs for collisions...";
        seen_phys_addr  := (others => false);
        duplicate_found := false;
        reversal        <= '0';

        for i in 0 to TEST_SPACE - 1 loop
            logical_address <= x"A5" & std_logic_vector(to_unsigned(i, 16)) & x"5A";
            wait for 2 ns; -- Allow combinational propagation through switch stages

            -- Invariance checks for unpermuted bits
            assert physical_address(31 downto 24) = x"A5"
                report "[FATAL] Bits [31:24] corrupted!" severity failure;
            assert physical_address(7 downto 0) = x"5A"
                report "[FATAL] Bits [7:0] corrupted!" severity failure;

            curr_phys_slice := physical_address(23 downto 8);
            phys_int        := to_integer(unsigned(curr_phys_slice));

            -- Check if another logical address already mapped to this physical address
            if seen_phys_addr(phys_int) then
                report "[FATAL] Collision Detected! Two inputs mapped to physical address 0x" &
                       to_hstring(curr_phys_slice) severity failure;
                duplicate_found := true;
            else
                seen_phys_addr(phys_int) := true;
            end if;

            -- Record mapping to verify determinism in the next step
            baseline_map(i) := curr_phys_slice;
        end loop;

        assert not duplicate_found
            report "[FAIL] Mapping is not bijective!" severity failure;
        report "[PASS] Case 2: Injective Check Passed. All 65,536 inputs mapped to unique outputs.";

        -- =========================================================
        -- TEST CASE 1 (Part B): Deterministic Verification
        -- =========================================================
        report "[TESTBENCH] Verifying Determinism (Same Key => Same Mapping)...";
        for i in 0 to TEST_SPACE - 1 loop
            logical_address <= x"A5" & std_logic_vector(to_unsigned(i, 16)) & x"5A";
            wait for 2 ns;

            assert physical_address(23 downto 8) = baseline_map(i)
                report "[FATAL] Non-deterministic mapping detected at index " & integer'image(i)
                severity failure;
        end loop;
        report "[PASS] Case 1: Deterministic Check Passed. Each address maps to one and only one address.";

        -- =========================================================
        -- TEST CASE 3: Bidirectional / Inversion Verification
        -- Forward (reversal = '0') maps LogAddr -> PhysAddr.
        -- Reverse (reversal = '1') maps PhysAddr -> LogAddr.
        -- =========================================================
        report "[TESTBENCH] Running Test Case 3: Testing Exact Inversion (PhysAddr -> LogAddr)...";

        -- Sweep all 65,536 addresses to verify exact bidirectional recovery
        for i in 0 to TEST_SPACE - 1 loop
            orig_log_addr := x"B4" & std_logic_vector(to_unsigned(i, 16)) & x"4B";

            -- Step 1: Forward evaluation (reversal = '0')
            reversal        <= '0';
            logical_address <= orig_log_addr;
            wait for 2 ns;
            fwd_phys_addr   := physical_address;

            -- Step 2: Feed output back into input and activate reverse mode (reversal = '1')
            reversal        <= '1';
            logical_address <= fwd_phys_addr;
            wait for 2 ns;
            recovered_addr  := physical_address;

            -- Step 3: Assert recovered address equals original address
            assert recovered_addr = orig_log_addr
                report "[FATAL] Inversion Mismatch!" & LF &
                       "  Original Address:  0x" & to_hstring(orig_log_addr) & LF &
                       "  Forward Mapped:    0x" & to_hstring(fwd_phys_addr) & LF &
                       "  Recovered Address: 0x" & to_hstring(recovered_addr)
                severity failure;
        end loop;

        report "[PASS] Case 3: Inverse Mapping Verified. All 65,536 addresses recovered successfully.";

        -- =========================================================
        -- TEST CASE 4: Key Churn Dynamics
        -- =========================================================
        report "[TESTBENCH] Running Test Case 4: Churning Key and Checking Output Diversification...";
        reversal <= '0';
        pulse_churn;

        is_different := false;
        for i in 0 to 255 loop
            logical_address <= x"A5" & std_logic_vector(to_unsigned(i, 16)) & x"5A";
            wait for 2 ns;

            if physical_address(23 downto 8) /= baseline_map(i) then
                is_different := true;
            end if;
        end loop;

        assert is_different
            report "[FATAL] Key churn failed: Physical address did not change across sampled space!"
            severity failure;
        report "[PASS] Case 4: Key Churn Verified. New distinct permutation active.";

        -- Finish Simulation
        report "[ALL TESTS PASSED] Network passed determinism, bijectivity, exact inverse mapping, and rekeying.";
        sim_done <= true;
        wait;
    end process stim_proc;

end architecture sim;