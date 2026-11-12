library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity amtd_ram_arbiter is
    generic (
        ROW_ADDR_W   : integer := 8;    -- Bit width of physical row address
        BLK_IDX_W    : integer := 4;    -- Bit width of block offset within a row
        DATA_W       : integer := 512;  -- Width of 1 memory block (e.g., 64B = 512 bits)
        STARVE_LIMIT : integer := 1024  -- Max stalled cycles before Churn priority boost
    );
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;

        -- Master 0: CPU / Address Translation Unit Interface (High Priority)
        cpu_req        : in  std_logic;
        cpu_we         : in  std_logic; -- '0' = Read, '1' = Write
        cpu_row_addr   : in  std_logic_vector(ROW_ADDR_W - 1 downto 0);
        cpu_blk_idx    : in  std_logic_vector(BLK_IDX_W - 1 downto 0);
        cpu_wdata      : in  std_logic_vector(DATA_W - 1 downto 0);
        cpu_grant      : out std_logic;
        cpu_rvalid     : out std_logic;
        cpu_rdata      : out std_logic_vector(DATA_W - 1 downto 0);

        -- Master 1: Churn Engine Interface (Low Priority)
        churn_req      : in  std_logic;
        churn_we       : in  std_logic; -- '0' = Read, '1' = Write
        churn_erase    : in  std_logic; -- Asserted 1 cycle after read to zero-out block
        churn_row_addr : in  std_logic_vector(ROW_ADDR_W - 1 downto 0);
        churn_blk_idx  : in  std_logic_vector(BLK_IDX_W - 1 downto 0);
        churn_wdata    : in  std_logic_vector(DATA_W - 1 downto 0);
        churn_grant    : out std_logic;
        churn_rvalid   : out std_logic;
        churn_rdata    : out std_logic_vector(DATA_W - 1 downto 0);

        -- Slave: Single-Port RAM Interface
        ram_en         : out std_logic;
        ram_we         : out std_logic;
        ram_addr       : out std_logic_vector(ROW_ADDR_W + BLK_IDX_W - 1 downto 0);
        ram_wdata      : out std_logic_vector(DATA_W - 1 downto 0);
        ram_rdata      : in  std_logic_vector(DATA_W - 1 downto 0);
        ram_rvalid     : in  std_logic
    );
end entity amtd_ram_arbiter;

architecture behavioral of amtd_ram_arbiter is

    type state_t is (
        S_IDLE,
        S_CPU_READ,
        S_CPU_WRITE,
        S_CHURN_READ,
        S_CHURN_ERASE_CHECK,
        S_CHURN_WRITE
    );
    signal state : state_t := S_IDLE;

    -- Latched address for atomic Churn Read -> Erase sequence
    signal latched_churn_addr : std_logic_vector(ROW_ADDR_W + BLK_IDX_W - 1 downto 0) := (others => '0');

    -- Anti-starvation watchdog counter
    signal starve_cnt : integer range 0 to STARVE_LIMIT := 0;

begin

    -- Broadcast read data bus; masters qualify data using their gated *_rvalid strobe
    cpu_rdata   <= ram_rdata;
    churn_rdata <= ram_rdata;

    -- Gate read-valid strobes strictly to the active bus owner
    cpu_rvalid   <= ram_rvalid when (state = S_CPU_READ)   else '0';
    churn_rvalid <= ram_rvalid when (state = S_CHURN_READ) else '0';

    process(clk, rst_n)
        variable churn_is_starved : boolean;
    begin
        if rst_n = '0' then
            state              <= S_IDLE;
            cpu_grant          <= '0';
            churn_grant        <= '0';
            ram_en             <= '0';
            ram_we             <= '0';
            ram_addr           <= (others => '0');
            ram_wdata          <= (others => '0');
            latched_churn_addr <= (others => '0');
            starve_cnt         <= 0;

        elsif rising_edge(clk) then
            -- Default single-cycle pulse de-assertions
            cpu_grant   <= '0';
            churn_grant <= '0';
            ram_en      <= '0';
            ram_we      <= '0';

            -- Anti-starvation watchdog counter update
            if churn_req = '0' then
                starve_cnt <= 0;
            elsif (state = S_IDLE) and (churn_req = '1') then
                -- Will be reset below if granted; otherwise increment
                if starve_cnt < STARVE_LIMIT then
                    starve_cnt <= starve_cnt + 1;
                end if;
            elsif (state /= S_CHURN_READ) and (state /= S_CHURN_ERASE_CHECK) and (state /= S_CHURN_WRITE) then
                -- Churn is waiting while CPU owns the bus
                if starve_cnt < STARVE_LIMIT then
                    starve_cnt <= starve_cnt + 1;
                end if;
            end if;

            churn_is_starved := (starve_cnt >= STARVE_LIMIT);

            case state is

                ----------------------------------------------------------------
                -- IDLE: Arbitrate between CPU (High Priority) and Churn Engine
                ----------------------------------------------------------------
                when S_IDLE =>
                    if (churn_req = '1') and churn_is_starved then
                        -- Watchdog override: grant 1 transaction to Churn Engine
                        churn_grant        <= '1';
                        starve_cnt         <= 0;
                        ram_en             <= '1';
                        ram_we             <= churn_we;
                        ram_addr           <= churn_row_addr & churn_blk_idx;
                        ram_wdata          <= churn_wdata;
                        latched_churn_addr <= churn_row_addr & churn_blk_idx;

                        if churn_we = '1' then
                            state <= S_CHURN_WRITE;
                        else
                            state <= S_CHURN_READ;
                        end if;

                    elsif cpu_req = '1' then
                        -- Standard priority: CPU wins when present
                        cpu_grant <= '1';
                        ram_en    <= '1';
                        ram_we    <= cpu_we;
                        ram_addr  <= cpu_row_addr & cpu_blk_idx;
                        ram_wdata <= cpu_wdata;

                        if cpu_we = '1' then
                            state <= S_CPU_WRITE;
                        else
                            state <= S_CPU_READ;
                        end if;

                    elsif churn_req = '1' then
                        -- Background access: Churn Engine uses idle bus
                        churn_grant        <= '1';
                        starve_cnt         <= 0;
                        ram_en             <= '1';
                        ram_we             <= churn_we;
                        ram_addr           <= churn_row_addr & churn_blk_idx;
                        ram_wdata          <= churn_wdata;
                        latched_churn_addr <= churn_row_addr & churn_blk_idx;

                        if churn_we = '1' then
                            state <= S_CHURN_WRITE;
                        else
                            state <= S_CHURN_READ;
                        end if;
                    end if;

                ----------------------------------------------------------------
                -- CPU ACTIVE STATES (Locked until transaction finishes)
                ----------------------------------------------------------------
                when S_CPU_READ =>
                    if ram_rvalid = '1' then
                        state <= S_IDLE;
                    end if;

                when S_CPU_WRITE =>
                    -- 1-cycle recovery state ensures CPU drops cpu_req before next grant
                    state <= S_IDLE;

                ----------------------------------------------------------------
                -- CHURN ACTIVE STATES (Locked until Read + Erase or Write finishes)
                ----------------------------------------------------------------
                when S_CHURN_READ =>
                    if ram_rvalid = '1' then
                        -- Transition to check if Churn Engine pulses churn_erase
                        -- on the cycle it latches ram_rdata
                        state <= S_CHURN_ERASE_CHECK;
                    end if;

                when S_CHURN_ERASE_CHECK =>
                    if churn_erase = '1' then
                        -- Atomically zero-out the just-read RAM block before releasing bus
                        ram_en    <= '1';
                        ram_we    <= '1';
                        ram_addr  <= latched_churn_addr;
                        ram_wdata <= (others => '0');
                    end if;
                    state <= S_IDLE;

                when S_CHURN_WRITE =>
                    -- 1-cycle recovery state ensures Churn drops churn_req before next grant
                    state <= S_IDLE;

            end case;
        end if;
    end process;

end architecture behavioral;