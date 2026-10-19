library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity trng_sim_model is
    generic (
        SEED1_INIT : positive := 12345;
        SEED2_INIT : positive := 67890
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        req      : in  std_logic;                    -- Trigger a new random key
        valid    : out std_logic;
        rand_key : out std_logic_vector(55 downto 0) -- 56-bit switch vector
    );
end entity trng_sim_model;

architecture sim of trng_sim_model is
begin

    process(clk, rst_n)
        variable s1     : positive := SEED1_INIT;
        variable s2     : positive := SEED2_INIT;
        variable r_real : real;
        variable r_int  : integer;
        variable temp   : std_logic_vector(55 downto 0);
    begin
        if rst_n = '0' then
            rand_key <= (others => '0');
            valid    <= '0';
        elsif rising_edge(clk) then
            valid <= '0';
            if req = '1' then
                -- Generate 56 bits in chunks using UNIFORM (chunks of 14 bits fit cleanly in positive integers)
                for i in 0 to 3 loop
                    uniform(s1, s2, r_real);
                    -- Scale 0.0 .. 1.0 to a 14-bit integer (0 to 16383)
                    r_int := integer(floor(r_real * 16384.0));
                    if r_int >= 16384 then
                        r_int := 16383;
                    end if;
                    temp((i + 1) * 14 - 1 downto i * 14) := std_logic_vector(to_unsigned(r_int, 14));
                end loop;

                rand_key <= temp;
                valid    <= '1';
            end if;
        end if;
    end process;

end architecture sim;