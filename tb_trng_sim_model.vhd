library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_trng_sim_model is
end entity tb_trng_sim_model;

architecture sim of tb_trng_sim_model is

    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal req      : std_logic := '0';
    signal valid    : std_logic;
    signal rand_key : std_logic_vector(55 downto 0);
    signal sim_done : boolean   := false;

    function to_hstring_56(slv : std_logic_vector(55 downto 0)) return string is
        constant HEX_LUT : string(1 to 16) := "0123456789ABCDEF";
        variable res     : string(1 to 14);
        variable nibble  : std_logic_vector(3 downto 0);
        variable val     : integer;
    begin
        for i in 0 to 13 loop
            nibble := slv(55 - (i * 4) downto 52 - (i * 4));
            val    := to_integer(unsigned(nibble));
            res(i + 1) := HEX_LUT(val + 1);
        end loop;
        return res;
    end function to_hstring_56;

begin

    dut: entity work.trng_sim_model
        generic map (
            SEED1_INIT => 12345,
            SEED2_INIT => 67890
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            req      => req,
            valid    => valid,
            rand_key => rand_key
        );

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

    stim_proc: process
        variable prev_vector : std_logic_vector(55 downto 0) := (others => '0');
        variable curr_vector : std_logic_vector(55 downto 0);
        variable bit_diff    : integer;
    begin
        -- Reset Phase
        rst_n <= '0';
        req   <= '0';
        wait for 25 ns;

        wait until falling_edge(clk);
        rst_n <= '1';

        wait until rising_edge(clk);
        wait for 1 ns;

        assert (valid = '0')
            report "Error: valid asserted immediately after reset without req!"
            severity error;
        assert (rand_key = (55 downto 0 => '0'))
            report "Error: rand_key not cleared after reset!"
            severity error;

        -- Test 10 Consecutive Epoch Remappings
        for epoch in 1 to 10 loop
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- Pulse req for 1 clock cycle
            req <= '1';
            wait until rising_edge(clk);
            req <= '0';

            -- Sample output on the cycle where valid is driven
            wait for 1 ns;

            assert (valid = '1')
                report "Error: valid did not assert on epoch " & integer'image(epoch)
                severity error;

            curr_vector := rand_key;

            -- Calculate Hamming distance
            bit_diff := 0;
            if epoch > 1 then
                for b in 0 to 55 loop
                    if curr_vector(b) /= prev_vector(b) then
                        bit_diff := bit_diff + 1;
                    end if;
                end loop;

                report "Epoch " & integer'image(epoch) & 
                       " Key: 0x" & to_hstring_56(curr_vector) & 
                       " | Flipped bits: " & integer'image(bit_diff) & " / 56";

                assert (curr_vector /= prev_vector)
                    report "Error: Stagnant key detected between epochs!"
                    severity failure;
            else
                report "Epoch 1 Initial Key: 0x" & to_hstring_56(curr_vector);
            end if;

            prev_vector := curr_vector;

            -- Wait for valid to deassert on the next rising edge
            wait until rising_edge(clk);
            wait for 1 ns;
            assert (valid = '0')
                report "Error: valid remained high for more than 1 cycle!"
                severity error;
        end loop;

        report "=== TRNG SIMULATION MODEL VERIFICATION PASSED ===" severity note;

        wait for CLK_PERIOD * 3;
        sim_done <= true;
        wait;
    end process stim_proc;

end architecture sim;