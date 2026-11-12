library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity double_permutation_network is
    port(
        logical_address  : in  STD_LOGIC_VECTOR(31 downto 0);
        clk, rst, churn  : in  STD_LOGIC;
        reversal         : in  STD_LOGIC;
        physical_address : out STD_LOGIC_VECTOR(31 downto 0)
    );
end entity double_permutation_network;

architecture dflt of double_permutation_network is

    signal tnrg_key                    : STD_LOGIC_VECTOR(55 downto 0);
    signal key_1, key_2, key1_reverse : STD_LOGIC_VECTOR(55 downto 0);
    signal active_key                  : STD_LOGIC_VECTOR(55 downto 0);

    component permutation_network
        port( 
            logical_address  : in  STD_LOGIC_VECTOR(31 downto 0);
            key              : in  STD_LOGIC_VECTOR(55 downto 0);
            physical_address : out STD_LOGIC_VECTOR(31 downto 0)
        );
    end component permutation_network;

    component trng_sim_model
        generic (
            SEED1_INIT : positive := 12345;
            SEED2_INIT : positive := 67890
        );
        port( 
            clk      : in  std_logic;
            rst_n    : in  std_logic;
            req      : in  std_logic;
            valid    : out std_logic;
            rand_key : out std_logic_vector(55 downto 0)
        );
    end component trng_sim_model;

    component n_bit_register
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

    component mux2to1_nbit
        generic (
            N : positive := 32
        );
        port (
            d0  : in  std_logic_vector(N - 1 downto 0);
            d1  : in  std_logic_vector(N - 1 downto 0);
            sel : in  std_logic;
            y   : out std_logic_vector(N - 1 downto 0)
        );
    end component mux2to1_nbit;

begin
    
    gen_stage_rev: for s in 0 to 6 generate
        key1_reverse(8*s + 7 downto 8*s) <= key_1(8*(6 - s) + 7 downto 8*(6 - s));
    end generate gen_stage_rev;

    rng : trng_sim_model
        generic map(
            SEED1_INIT => 12345,
            SEED2_INIT => 67890
        )
        port map(
            clk      => clk,
            rst_n    => rst,
            req      => churn,
            valid    => open,
            rand_key => tnrg_key
        );

    key1 : n_bit_register
        generic map(
            N => 56
        )
        port map(
            clk   => clk,
            rst_n => rst,
            load  => churn,
            d     => tnrg_key,
            q     => key_1
        );

    key2 : n_bit_register
        generic map(
            N => 56
        )
        port map(
            clk   => clk,
            rst_n => rst,
            load  => churn,
            d     => key1_reverse,
            q     => key_2
        );

    key_mux : mux2to1_nbit
        generic map(
            N => 56
        )
        port map(
            d0  => key_1,
            d1  => key_2,
            sel => reversal,
            y   => active_key
        );

    perm_single : permutation_network
        port map(
            logical_address  => logical_address,
            key              => active_key,
            physical_address => physical_address
        );

end architecture dflt;