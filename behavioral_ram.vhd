library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity behavioral_ram is
    generic (
        ROW_ADDR_W  : integer := 8;    -- Bit width of physical row address
        BLK_IDX_W   : integer := 4;    -- Bit width of block offset within a row
        DATA_W      : integer := 512;  -- Width of 1 memory block (e.g., 64B = 512 bits)
        INIT_TAGGED : boolean := true  -- True: pre-load each block with its initial address on reset
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;

        -- Slave Interface (Connects directly to amtd_ram_arbiter)
        ram_en     : in  std_logic;
        ram_we     : in  std_logic; -- '0' = Read, '1' = Write
        ram_addr   : in  std_logic_vector(ROW_ADDR_W + BLK_IDX_W - 1 downto 0);
        ram_wdata  : in  std_logic_vector(DATA_W - 1 downto 0);
        ram_rdata  : out std_logic_vector(DATA_W - 1 downto 0);
        ram_rvalid : out std_logic
    );
end entity behavioral_ram;

architecture behavioral of behavioral_ram is

    constant ADDR_W : integer := ROW_ADDR_W + BLK_IDX_W;
    constant DEPTH  : integer := 2 ** ADDR_W;

    type ram_array_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_W - 1 downto 0);
    signal mem : ram_array_t := (others => (others => '0'));

begin

    process(clk, rst_n)
        variable addr_int : integer range 0 to DEPTH - 1;
    begin
        if rst_n = '0' then
            ram_rdata  <= (others => '0');
            ram_rvalid <= '0';

            for idx in 0 to DEPTH - 1 loop
                if INIT_TAGGED then
                    -- Tag each block with its original (Row & Block_Idx) coordinate
                    mem(idx) <= std_logic_vector(to_unsigned(idx, DATA_W));
                else
                    mem(idx) <= (others => '0');
                end if;
            end loop;

        elsif rising_edge(clk) then
            -- Default single-cycle strobe de-assertion
            ram_rvalid <= '0';

            if ram_en = '1' then
                addr_int := to_integer(unsigned(ram_addr));

                if ram_we = '1' then
                    -- Synchronous Write (also handles Churn Erase zero-writes)
                    mem(addr_int) <= ram_wdata;
                else
                    -- Synchronous Read (1-cycle latency)
                    ram_rdata  <= mem(addr_int);
                    ram_rvalid <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture behavioral;