library ieee;
use ieee.std_logic_1164.all;

entity permutation_network is
    port( logical_address : in STD_LOGIC_VECTOR(31 downto 0);
        clk, rst, churn : in STD_LOGIC;
        physical_address : out STD_LOGIC_VECTOR(31 downto 0)
    );
end entity permutation_network;

architecture dflt of permutation_network is
    signal stage_0, stage_1, stage_2, stage_3, stage_4, stage_5, stage_6, stage_7 : STD_LOGIC_VECTOR(15 downto 0);
    signal key : STD_LOGIC_VECTOR(55 downto 0); 
    component trng_sim_model
            port( clk      : in  std_logic;
        rst_n    : in  std_logic;
        req      : in  std_logic;                    -- Trigger a new random key
        valid    : out std_logic;
        rand_key : out std_logic_vector(55 downto 0) -- 56-bit switch vector

            );
        end component trng_sim_model;

        component switch
            port( x : in STD_LOGIC_VECTOR(1 downto 0);
                sel : in STD_LOGIC;
                y : out STD_LOGIC_VECTOR(1 downto 0)
            );
        end component switch;
    begin
        
        rng : trng_sim_model
            port map(
                clk => clk,
                rst_n => rst,
                req => churn,
                valid => open,
                rand_key => key
            );

    gen_stage_0: for i in 0 to 7 generate
        sw_inst: switch
            port map (
                x(0) => stage_0(2*i),
                x(1) => stage_0(2*i + 1),
                sel  => key(i),
                y(0) => stage_1(2*i),
                y(1) => stage_1(2*i + 1)
            );
    end generate gen_stage_0;

    gen_stage_1_subnets: for g in 0 to 1 generate
        gen_stage_1_switches: for i in 0 to 3 generate
            sw_inst: switch
                port map (
                    x(0) => stage_1(8*g + 2*i),
                    x(1) => stage_1(8*g + 2*i + 1),
                    sel  => key(8 + 4*g + i),
                    y(0) => stage_2(8*g + i),
                    y(1) => stage_2(8*g + i + 4)
                );
        end generate gen_stage_1_switches;
    end generate gen_stage_1_subnets;

    gen_stage_2_subnets: for g in 0 to 3 generate
        gen_stage_2_switches: for i in 0 to 1 generate
            sw_inst: switch
                port map (
                    x(0) => stage_2(4*g + 2*i),
                    x(1) => stage_2(4*g + 2*i + 1),
                    sel  => key(16 + 2*g + i),
                    y(0) => stage_3(4*g + i),
                    y(1) => stage_3(4*g + i + 2)
                );
        end generate gen_stage_2_switches;
    end generate gen_stage_2_subnets;

    gen_stage_3_subnets: for g in 0 to 3 generate
        gen_stage_3_switches: for i in 0 to 1 generate
            sw_inst: switch
                port map (
                    x(0) => stage_3(4*g + 2*i),
                    x(1) => stage_3(4*g + 2*i + 1),
                    sel  => key(24 + 2*g + i),
                    y(0) => stage_4(4*g + i),
                    y(1) => stage_4(4*g + i + 2)
                );
        end generate gen_stage_3_switches;
    end generate gen_stage_3_subnets;

    gen_stage_4_subnets: for g in 0 to 1 generate
        gen_stage_4_switches: for i in 0 to 3 generate
            sw_inst: switch
                port map (
                    x(0) => stage_4(8*g + 2*i),
                    x(1) => stage_4(8*g + 2*i + 1),
                    sel  => key(32 + 4*g + i),
                    y(0) => stage_5(8*g + i),
                    y(1) => stage_5(8*g + i + 4)
                );
        end generate gen_stage_4_switches;
    end generate gen_stage_4_subnets;

    gen_stage_5: for i in 0 to 7 generate
        sw_inst: switch
            port map (
                x(0) => stage_5(2*i),
                x(1) => stage_5(2*i + 1),
                sel  => key(40 + i),
                y(0) => stage_6(i),
                y(1) => stage_6(i + 8)
            );
    end generate gen_stage_5;

    gen_stage_6: for i in 0 to 7 generate
        sw_inst: switch
            port map (
                x(0) => stage_6(2*i),
                x(1) => stage_6(2*i + 1),
                sel  => key(48 + i),
                y(0) => stage_7(2*i),
                y(1) => stage_7(2*i + 1)
            );
    end generate gen_stage_6;

    stage_0 <= logical_address(23 downto 8);

    physical_address(31 downto 24) <= logical_address(31 downto 24);
    physical_address(23 downto 8)  <= stage_7;
    physical_address(7 downto 0) <= logical_address(7 downto 0);

    end architecture dflt;
