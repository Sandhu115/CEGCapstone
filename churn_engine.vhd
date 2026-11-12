library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity churn_engine is
    generic (
        ROW_ADDR_W     : integer := 8;   -- Width of row address (e.g., 8 bits -> 256 rows)
        BLK_IDX_W      : integer := 4;   -- Width of block index within a row
        BLOCKS_PER_ROW : integer := 16;  -- 'n' = number of blocks per row
        DATA_W         : integer := 512  -- Width of 1 block (e.g., 64 bytes = 512 bits)
    );
    port (
        clk                  : in  std_logic;
        rst_n                : in  std_logic;
        start_churn          : in  std_logic; -- Enable/trigger signal to begin churning

        -- Key Generator Interface (Step 2)
        gen_key              : out std_logic;

        -- Permutation / "Future" Address Lookup Interface (Steps 4 & 7)
        -- Connects combinationally (or registered) to your Benes network / mapping logic
        curr_row_query       : out std_logic_vector(ROW_ADDR_W - 1 downto 0);
        future_row_in        : in  std_logic_vector(ROW_ADDR_W - 1 downto 0);

        -- Flag Table Interface (Margin notes & Step 1)
        lowest_unchurned_row : in  std_logic_vector(ROW_ADDR_W - 1 downto 0);
        all_rows_churned     : in  std_logic; -- High when flag table has no unchurned rows left
        flag_we              : out std_logic;
        flag_row_addr        : out std_logic_vector(ROW_ADDR_W - 1 downto 0);
        flag_blk_idx         : out std_logic_vector(BLK_IDX_W - 1 downto 0);
        flag_set_churned     : out std_logic; -- '1' = block migrated to future loc
        flag_set_erased      : out std_logic; -- '1' = block erased/vacated in RAM
        ram_blk_is_erased    : in  std_logic; -- Flag table status of currently addressed RAM block

        -- Single-Port RAM / Arbiter Interface (Steps 3, 4, 5, 7, 8)
        ram_req              : out std_logic;
        ram_we               : out std_logic; -- '0' = Read, '1' = Write
        ram_erase            : out std_logic; -- High when erasing/zeroing RAM block
        ram_row_addr         : out std_logic_vector(ROW_ADDR_W - 1 downto 0);
        ram_blk_idx          : out std_logic_vector(BLK_IDX_W - 1 downto 0);
        ram_wdata            : out std_logic_vector(DATA_W - 1 downto 0);
        ram_grant            : in  std_logic; -- Arbiter grants bus to Churn Engine
        ram_rvalid           : in  std_logic; -- Read data valid from RAM
        ram_rdata            : in  std_logic_vector(DATA_W - 1 downto 0);

        -- Status
        churn_done           : out std_logic
    );
end entity churn_engine;

architecture behavioral of churn_engine is

    -- 10-Step FSM matching handwritten pseudocode
    type state_t is (
        S1_CHECK_START,
        S2_GEN_KEY,
        S3_REQ_UNCHURNED,
        S3_WAIT_READ,
        S4_REQ_FUTURE,
        S4_WAIT_READ,
        S5_WRITE_FUTURE,
        S6_LOAD_BLK_BUF,
        S7_REQ_FUTURE,
        S7_WAIT_READ,
        S8_WRITE_FUTURE,
        S9_INC_CHECK,
        S10_CYCLE_CHECK
    );
    signal state : state_t := S1_CHECK_START;

    -- 1-Block Buffer & Metadata
    signal block_buffer    : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
    signal block_buf_valid : std_logic := '0';
    signal block_buf_row   : std_logic_vector(ROW_ADDR_W - 1 downto 0) := (others => '0');

    -- Full-Row Buffer (n blocks) & Metadata
    type row_buf_t is array (0 to BLOCKS_PER_ROW - 1) of std_logic_vector(DATA_W - 1 downto 0);
    signal row_buffer      : row_buf_t := (others => (others => '0'));
    signal row_buf_valid   : std_logic_vector(BLOCKS_PER_ROW - 1 downto 0) := (others => '0');
    signal row_buf_row     : std_logic_vector(ROW_ADDR_W - 1 downto 0) := (others => '0');

    -- Block index counter 'i' (0 to n)
    signal i               : integer range 0 to BLOCKS_PER_ROW := 0;

    -- Helper constant for 0x00 row check
    constant ZERO_ROW      : std_logic_vector(ROW_ADDR_W - 1 downto 0) := (others => '0');

begin

    -- Continuously query the "Future" row of whatever row is currently tagged in block_buffer
    curr_row_query <= block_buf_row;

    process(clk, rst_n)
        variable both_buffers_empty : boolean;
    begin
        if rst_n = '0' then
            state            <= S1_CHECK_START;
            i                <= 0;
            block_buffer     <= (others => '0');
            block_buf_valid  <= '0';
            block_buf_row    <= (others => '0');
            row_buffer       <= (others => (others => '0'));
            row_buf_valid    <= (others => '0');
            row_buf_row      <= (others => '0');
            gen_key          <= '0';
            flag_we          <= '0';
            flag_row_addr    <= (others => '0');
            flag_blk_idx     <= (others => '0');
            flag_set_churned <= '0';
            flag_set_erased  <= '0';
            ram_req          <= '0';
            ram_we           <= '0';
            ram_erase        <= '0';
            ram_row_addr     <= (others => '0');
            ram_blk_idx      <= (others => '0');
            ram_wdata        <= (others => '0');
            churn_done       <= '0';

        elsif rising_edge(clk) then
            -- Default single-cycle pulse de-assertions
            gen_key          <= '0';
            flag_we          <= '0';
            flag_set_churned <= '0';
            flag_set_erased  <= '0';
            ram_erase        <= '0';
            churn_done       <= '0';

            both_buffers_empty := (block_buf_valid = '0') and
                                  (row_buf_valid = (row_buf_valid'range => '0'));

            case state is

                ----------------------------------------------------------------
                -- STEP 1: Check start condition & whether a new key is needed
                ----------------------------------------------------------------
                when S1_CHECK_START =>
                    i <= 0;
                    if all_rows_churned = '1' then
                        churn_done <= '1';
                    elsif start_churn = '1' then
                        if both_buffers_empty and (lowest_unchurned_row = ZERO_ROW) then
                            state <= S2_GEN_KEY;       -- New global epoch -> generate key
                        else
                            state <= S3_REQ_UNCHURNED; -- Mid-epoch -> keep current key
                        end if;
                    end if;

                ----------------------------------------------------------------
                -- STEP 2: Generate new permutation key (GenKey = 1)
                ----------------------------------------------------------------
                when S2_GEN_KEY =>
                    gen_key <= '1';
                    state   <= S3_REQ_UNCHURNED;

                ----------------------------------------------------------------
                -- STEP 3: Request i-th block of lowest_unchurned_row into block_buffer
                --         + Erase RAM block & Update Flags
                ----------------------------------------------------------------
                when S3_REQ_UNCHURNED =>
                    ram_req      <= '1';
                    ram_we       <= '0'; -- Read
                    ram_row_addr <= lowest_unchurned_row;
                    ram_blk_idx  <= std_logic_vector(to_unsigned(i, BLK_IDX_W));

                    if ram_grant = '1' then
                        ram_req <= '0';
                        state   <= S3_WAIT_READ;
                    end if;

                when S3_WAIT_READ =>
                    if ram_rvalid = '1' then
                        block_buffer    <= ram_rdata;
                        block_buf_valid <= '1';
                        block_buf_row   <= lowest_unchurned_row;

                        -- Margin note: Erase RAM block & Update Flags
                        ram_erase       <= '1';
                        flag_we         <= '1';
                        flag_row_addr   <= lowest_unchurned_row;
                        flag_blk_idx    <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                        flag_set_erased <= '1';

                        state           <= S4_REQ_FUTURE;
                    end if;

                ----------------------------------------------------------------
                -- STEP 4: Find "Future" location of block_buffer, read that
                --         block from RAM into row_buffer(i), erase & update flag
                ----------------------------------------------------------------
                when S4_REQ_FUTURE =>
                    ram_req      <= '1';
                    ram_we       <= '0'; -- Read
                    ram_row_addr <= future_row_in;
                    ram_blk_idx  <= std_logic_vector(to_unsigned(i, BLK_IDX_W));

                    if ram_grant = '1' then
                        ram_req <= '0';
                        state   <= S4_WAIT_READ;
                    end if;

                when S4_WAIT_READ =>
                    if ram_rvalid = '1' then
                        row_buf_row <= future_row_in;

                        -- Only save valid data if the target RAM block wasn't already erased
                        if ram_blk_is_erased = '0' then
                            row_buffer(i)    <= ram_rdata;
                            row_buf_valid(i) <= '1';
                        else
                            row_buf_valid(i) <= '0';
                        end if;

                        -- Margin note: Erase & Update flag in flag table
                        ram_erase       <= '1';
                        flag_we         <= '1';
                        flag_row_addr   <= future_row_in;
                        flag_blk_idx    <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                        flag_set_erased <= '1';

                        state           <= S5_WRITE_FUTURE;
                    end if;

                ----------------------------------------------------------------
                -- STEP 5: Write block_buffer to future row's block i, update flags,
                --         increment i. If i /= n -> Step 3, else reset i & -> Step 6
                ----------------------------------------------------------------
                when S5_WRITE_FUTURE =>
                    ram_req      <= '1';
                    ram_we       <= '1'; -- Write
                    ram_row_addr <= future_row_in;
                    ram_blk_idx  <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                    ram_wdata    <= block_buffer;

                    if ram_grant = '1' then
                        ram_req          <= '0';
                        ram_we           <= '0';
                        block_buf_valid  <= '0'; -- block_buffer now emptied to RAM

                        -- Margin note: Update Flags (mark destination block churned)
                        flag_we          <= '1';
                        flag_row_addr    <= future_row_in;
                        flag_blk_idx     <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                        flag_set_churned <= '1';

                        if (i + 1) /= BLOCKS_PER_ROW then
                            i     <= i + 1;
                            state <= S3_REQ_UNCHURNED;
                        else
                            i     <= 0; -- Reset i before entering Step 6 loop
                            state <= S6_LOAD_BLK_BUF;
                        end if;
                    end if;

                ----------------------------------------------------------------
                -- STEP 6: Move row_buffer(i) into block_buffer
                ----------------------------------------------------------------
                when S6_LOAD_BLK_BUF =>
                    block_buffer     <= row_buffer(i);
                    block_buf_valid  <= row_buf_valid(i);
                    block_buf_row    <= row_buf_row;
                    row_buf_valid(i) <= '0'; -- Slot i of row_buffer is now vacated

                    -- If block_buffer has valid data to displace, walk forward;
                    -- otherwise skip ahead to write/finish the loop
                    if row_buf_valid(i) = '1' then
                        state <= S7_REQ_FUTURE;
                    else
                        state <= S9_INC_CHECK;
                    end if;

                ----------------------------------------------------------------
                -- STEP 7: Find "Future" location of block_buffer, request from
                --         RAM & save to row_buffer(i), erase & update flags
                ----------------------------------------------------------------
                when S7_REQ_FUTURE =>
                    ram_req      <= '1';
                    ram_we       <= '0'; -- Read
                    ram_row_addr <= future_row_in;
                    ram_blk_idx  <= std_logic_vector(to_unsigned(i, BLK_IDX_W));

                    if ram_grant = '1' then
                        ram_req <= '0';
                        state   <= S7_WAIT_READ;
                    end if;

                when S7_WAIT_READ =>
                    if ram_rvalid = '1' then
                        row_buf_row <= future_row_in;

                        -- If future block was already erased (cycle closed back to start),
                        -- row_buffer(i) remains empty ('0')
                        if ram_blk_is_erased = '0' then
                            row_buffer(i)    <= ram_rdata;
                            row_buf_valid(i) <= '1';
                        else
                            row_buf_valid(i) <= '0';
                        end if;

                        -- Erase & Update Flags
                        ram_erase       <= '1';
                        flag_we         <= '1';
                        flag_row_addr   <= future_row_in;
                        flag_blk_idx    <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                        flag_set_erased <= '1';

                        state           <= S8_WRITE_FUTURE;
                    end if;

                ----------------------------------------------------------------
                -- STEP 8: Write block_buffer to RAM (future row) & update flags
                ----------------------------------------------------------------
                when S8_WRITE_FUTURE =>
                    ram_req      <= '1';
                    ram_we       <= '1'; -- Write
                    ram_row_addr <= future_row_in;
                    ram_blk_idx  <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                    ram_wdata    <= block_buffer;

                    if ram_grant = '1' then
                        ram_req          <= '0';
                        ram_we           <= '0';
                        block_buf_valid  <= '0'; -- block_buffer emptied

                        -- Margin note: Update flags
                        flag_we          <= '1';
                        flag_row_addr    <= future_row_in;
                        flag_blk_idx     <= std_logic_vector(to_unsigned(i, BLK_IDX_W));
                        flag_set_churned <= '1';

                        state            <= S9_INC_CHECK;
                    end if;

                ----------------------------------------------------------------
                -- STEP 9: Check if i = n - 1 -> Step 10, else increment i & -> Step 6
                ----------------------------------------------------------------
                when S9_INC_CHECK =>
                    if i = (BLOCKS_PER_ROW - 1) then
                        state <= S10_CYCLE_CHECK;
                    else
                        i     <= i + 1;
                        state <= S6_LOAD_BLK_BUF;
                    end if;

                ----------------------------------------------------------------
                -- STEP 10: Reset i. If both buffers empty -> Step 1 (loop closed),
                --          else -> Step 6 (continue permutation cycle)
                ----------------------------------------------------------------
                when S10_CYCLE_CHECK =>
                    i <= 0;
                    if both_buffers_empty then
                        state <= S1_CHECK_START;
                    else
                        state <= S6_LOAD_BLK_BUF;
                    end if;

            end case;
        end if;
    end process;

end architecture behavioral;