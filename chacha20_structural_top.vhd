library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chacha20_structural_top is
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        start         : in  std_logic;
        ready         : out std_logic;
        valid         : out std_logic;
        key_in        : in  std_logic_vector(255 downto 0);
        nonce_in      : in  std_logic_vector(95 downto 0);
        counter_in    : in  std_logic_vector(31 downto 0);
        keystream_out : out std_logic_vector(511 downto 0)
    );
end entity chacha20_structural_top;

architecture struct of chacha20_structural_top is

    -- Constant word definitions ("expand 32-byte k")
    constant CONST_0 : std_logic_vector(31 downto 0) := x"61707865";
    constant CONST_1 : std_logic_vector(31 downto 0) := x"3320646e";
    constant CONST_2 : std_logic_vector(31 downto 0) := x"79622d32";
    constant CONST_3 : std_logic_vector(31 downto 0) := x"6b206574";

    type word_array_16 is array (0 to 15) of std_logic_vector(31 downto 0);

    -- State register signals
    signal reg_d        : word_array_16;
    signal reg_q        : word_array_16;
    signal init_reg_d   : word_array_16;
    signal init_reg_q   : word_array_16;
    signal reg_load     : std_logic;
    signal init_load    : std_logic;

    -- QR Engine structural interconnects
    type qr_bus_4 is array (0 to 3) of std_logic_vector(31 downto 0);
    signal qru_a_in, qru_b_in, qru_c_in, qru_d_in     : qr_bus_4;
    signal qru_a_out, qru_b_out, qru_c_out, qru_d_out : qr_bus_4;

    -- Feed-forward structural adders
    signal ff_sum : word_array_16;

    -- Controller FSM
    type state_type is (S_IDLE, S_LOAD, S_ROUNDS, S_FEED_FORWARD, S_DONE);
    signal state_reg : state_type;
    signal round_ctr : unsigned(4 downto 0);
    signal is_diag   : std_logic;

begin

    -------------------------------------------------------------------------
    -- 1. Structural Register Banks: Initial State & Working State
    -------------------------------------------------------------------------
    -- Map inputs into Initial State Bus
    init_reg_d(0)  <= CONST_0;
    init_reg_d(1)  <= CONST_1;
    init_reg_d(2)  <= CONST_2;
    init_reg_d(3)  <= CONST_3;
    init_reg_d(4)  <= key_in(31 downto 0);
    init_reg_d(5)  <= key_in(63 downto 32);
    init_reg_d(6)  <= key_in(95 downto 64);
    init_reg_d(7)  <= key_in(127 downto 96);
    init_reg_d(8)  <= key_in(159 downto 128);
    init_reg_d(9)  <= key_in(191 downto 160);
    init_reg_d(10) <= key_in(223 downto 192);
    init_reg_d(11) <= key_in(255 downto 224);
    init_reg_d(12) <= counter_in;
    init_reg_d(13) <= nonce_in(31 downto 0);
    init_reg_d(14) <= nonce_in(63 downto 32);
    init_reg_d(15) <= nonce_in(95 downto 64);

    gen_registers: for i in 0 to 15 generate
        -- Initial state snapshot register (using n_bit_register generic)
        u_init_reg: entity work.n_bit_register
            generic map (
                N => 32
            )
            port map (
                clk   => clk,
                rst_n => rst_n,
                load  => init_load,
                d     => init_reg_d(i),
                q     => init_reg_q(i)
            );

        -- Active working state register (using n_bit_register generic)
        u_work_reg: entity work.n_bit_register
            generic map (
                N => 32
            )
            port map (
                clk   => clk,
                rst_n => rst_n,
                load  => reg_load,
                d     => reg_d(i),
                q     => reg_q(i)
            );

        -- Feed-Forward Adder (reg_q + init_reg_q)
        u_ff_adder: entity work.adder_32
            port map (
                a => reg_q(i),
                b => init_reg_q(i),
                s => ff_sum(i)
            );

        -- Output vector mapping
        keystream_out((i + 1) * 32 - 1 downto i * 32) <= ff_sum(i);
    end generate gen_registers;

    -------------------------------------------------------------------------
    -- 2. Permutation Network / Interconnect Multiplexers
    -------------------------------------------------------------------------
    is_diag <= round_ctr(0); -- '0' = Column Round, '1' = Diagonal Round

    -- QR Unit 0: Col(0,4,8,12) vs Diag(0,5,10,15)
    qru_a_in(0) <= reg_q(0);
    qru_b_in(0) <= reg_q(5)  when is_diag = '1' else reg_q(4);
    qru_c_in(0) <= reg_q(10) when is_diag = '1' else reg_q(8);
    qru_d_in(0) <= reg_q(15) when is_diag = '1' else reg_q(12);

    -- QR Unit 1: Col(1,5,9,13) vs Diag(1,6,11,12)
    qru_a_in(1) <= reg_q(1);
    qru_b_in(1) <= reg_q(6)  when is_diag = '1' else reg_q(5);
    qru_c_in(1) <= reg_q(11) when is_diag = '1' else reg_q(9);
    qru_d_in(1) <= reg_q(12) when is_diag = '1' else reg_q(13);

    -- QR Unit 2: Col(2,6,10,14) vs Diag(2,7,8,13)
    qru_a_in(2) <= reg_q(2);
    qru_b_in(2) <= reg_q(7)  when is_diag = '1' else reg_q(6);
    qru_c_in(2) <= reg_q(8)  when is_diag = '1' else reg_q(10);
    qru_d_in(2) <= reg_q(13) when is_diag = '1' else reg_q(14);

    -- QR Unit 3: Col(3,7,11,15) vs Diag(3,4,9,14)
    qru_a_in(3) <= reg_q(3);
    qru_b_in(3) <= reg_q(4)  when is_diag = '1' else reg_q(7);
    qru_c_in(3) <= reg_q(9)  when is_diag = '1' else reg_q(11);
    qru_d_in(3) <= reg_q(14) when is_diag = '1' else reg_q(15);

    -------------------------------------------------------------------------
    -- 3. Four Parallel Structural Quarter-Round Units
    -------------------------------------------------------------------------
    gen_qr: for j in 0 to 3 generate
        u_qr: entity work.quarter_round
            port map (
                a_in  => qru_a_in(j),
                b_in  => qru_b_in(j),
                c_in  => qru_c_in(j),
                d_in  => qru_d_in(j),
                a_out => qru_a_out(j),
                b_out => qru_b_out(j),
                c_out => qru_c_out(j),
                d_out => qru_d_out(j)
            );
    end generate gen_qr;

    -------------------------------------------------------------------------
    -- 4. Register Feedback Demultiplexers
    -------------------------------------------------------------------------
    demux_proc: process(state_reg, init_reg_d, is_diag, qru_a_out, qru_b_out, qru_c_out, qru_d_out)
    begin
        if (state_reg = S_IDLE or state_reg = S_LOAD) then
            reg_d <= init_reg_d;
        else
            if is_diag = '0' then
                -- Column writeback routing
                reg_d(0)  <= qru_a_out(0);
                reg_d(4)  <= qru_b_out(0);
                reg_d(8)  <= qru_c_out(0);
                reg_d(12) <= qru_d_out(0);

                reg_d(1)  <= qru_a_out(1);
                reg_d(5)  <= qru_b_out(1);
                reg_d(9)  <= qru_c_out(1);
                reg_d(13) <= qru_d_out(1);

                reg_d(2)  <= qru_a_out(2);
                reg_d(6)  <= qru_b_out(2);
                reg_d(10) <= qru_c_out(2);
                reg_d(14) <= qru_d_out(2);

                reg_d(3)  <= qru_a_out(3);
                reg_d(7)  <= qru_b_out(3);
                reg_d(11) <= qru_c_out(3);
                reg_d(15) <= qru_d_out(3);
            else
                -- Diagonal writeback routing
                reg_d(0)  <= qru_a_out(0);
                reg_d(5)  <= qru_b_out(0);
                reg_d(10) <= qru_c_out(0);
                reg_d(15) <= qru_d_out(0);

                reg_d(1)  <= qru_a_out(1);
                reg_d(6)  <= qru_b_out(1);
                reg_d(11) <= qru_c_out(1);
                reg_d(12) <= qru_d_out(1);

                reg_d(2)  <= qru_a_out(2);
                reg_d(7)  <= qru_b_out(2);
                reg_d(8)  <= qru_c_out(2);
                reg_d(13) <= qru_d_out(2);

                reg_d(3)  <= qru_a_out(3);
                reg_d(4)  <= qru_b_out(3);
                reg_d(9)  <= qru_c_out(3);
                reg_d(14) <= qru_d_out(3);
            end if;
        end if;
    end process demux_proc;

    -------------------------------------------------------------------------
    -- 5. Control FSM
    -------------------------------------------------------------------------
    ctrl_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            state_reg <= S_IDLE;
            round_ctr <= (others => '0');
            ready     <= '0';
            valid     <= '0';
            reg_load  <= '0';
            init_load <= '0';

        elsif rising_edge(clk) then
            case state_reg is

                when S_IDLE =>
                    valid     <= '0';
                    round_ctr <= (others => '0');
                    if start = '1' then
                        ready     <= '0';
                        init_load <= '1';
                        reg_load  <= '1';
                        state_reg <= S_LOAD;
                    else
                        ready     <= '1';
                        init_load <= '0';
                        reg_load  <= '0';
                    end if;

                when S_LOAD =>
                    init_load <= '0';
                    reg_load  <= '1';
                    round_ctr <= (others => '0');
                    state_reg <= S_ROUNDS;

                when S_ROUNDS =>
                    init_load <= '0';
                    if round_ctr = 19 then
                        reg_load  <= '0';
                        state_reg <= S_FEED_FORWARD;
                    else
                        reg_load  <= '1';
                        round_ctr <= round_ctr + 1;
                    end if;

                when S_FEED_FORWARD =>
                    reg_load  <= '0';
                    init_load <= '0';
                    valid     <= '1';
                    state_reg <= S_DONE;

                when S_DONE =>
                    valid     <= '0';
                    ready     <= '1';
                    state_reg <= S_IDLE;

            end case;
        end if;
    end process ctrl_proc;

end architecture struct;