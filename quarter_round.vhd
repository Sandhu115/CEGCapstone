library ieee;
use ieee.std_logic_1164.all;

entity quarter_round is
    port (
        a_in  : in  std_logic_vector(31 downto 0);
        b_in  : in  std_logic_vector(31 downto 0);
        c_in  : in  std_logic_vector(31 downto 0);
        d_in  : in  std_logic_vector(31 downto 0);
        a_out : out std_logic_vector(31 downto 0);
        b_out : out std_logic_vector(31 downto 0);
        c_out : out std_logic_vector(31 downto 0);
        d_out : out std_logic_vector(31 downto 0)
    );
end entity quarter_round;

architecture struct of quarter_round is

    -- Step 1 intermediate signals
    signal a_step1   : std_logic_vector(31 downto 0);
    signal xor_step1 : std_logic_vector(31 downto 0);
    signal d_step1   : std_logic_vector(31 downto 0);

    -- Step 2 intermediate signals
    signal c_step2   : std_logic_vector(31 downto 0);
    signal xor_step2 : std_logic_vector(31 downto 0);
    signal b_step2   : std_logic_vector(31 downto 0);

    -- Step 3 intermediate signals
    signal a_step3   : std_logic_vector(31 downto 0);
    signal xor_step3 : std_logic_vector(31 downto 0);
    signal d_step3   : std_logic_vector(31 downto 0);

    -- Step 4 intermediate signals
    signal c_step4   : std_logic_vector(31 downto 0);
    signal xor_step4 : std_logic_vector(31 downto 0);
    signal b_step4   : std_logic_vector(31 downto 0);

begin

    -- Step 1: a = a + b; d = (d xor a) <<< 16
    u_add1: entity work.adder_32
        port map (a => a_in, b => b_in, s => a_step1);

    xor_step1 <= d_in xor a_step1;

    u_rot16: entity work.rot_left_32
        generic map (SHIFT => 16)
        port map (din => xor_step1, dout => d_step1);

    -- Step 2: c = c + d; b = (b xor c) <<< 12
    u_add2: entity work.adder_32
        port map (a => c_in, b => d_step1, s => c_step2);

    xor_step2 <= b_in xor c_step2;

    u_rot12: entity work.rot_left_32
        generic map (SHIFT => 12)
        port map (din => xor_step2, dout => b_step2);

    -- Step 3: a = a + b; d = (d xor a) <<< 8
    u_add3: entity work.adder_32
        port map (a => a_step1, b => b_step2, s => a_step3);

    xor_step3 <= d_step1 xor a_step3;

    u_rot8: entity work.rot_left_32
        generic map (SHIFT => 8)
        port map (din => xor_step3, dout => d_step3);

    -- Step 4: c = c + d; b = (b xor c) <<< 7
    u_add4: entity work.adder_32
        port map (a => c_step2, b => d_step3, s => c_step4);

    xor_step4 <= b_step2 xor c_step4;

    u_rot7: entity work.rot_left_32
        generic map (SHIFT => 7)
        port map (din => xor_step4, dout => b_step4);

    -- Outputs
    a_out <= a_step3;
    b_out <= b_step4;
    c_out <= c_step4;
    d_out <= d_step3;

end architecture struct;