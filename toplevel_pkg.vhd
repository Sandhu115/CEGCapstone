library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package toplevel_pkg is

    -- =========================================================================
    -- Constants & Architecture Sizing
    -- =========================================================================
    constant ADDR_WIDTH          : natural := 32;
    constant DATA_WIDTH          : natural := 32;
    constant BLOCK_WIDTH         : natural := 16;
    constant OFFSET_WIDTH        : natural := 6;   -- 64-byte line
    
    -- Beneš network parameters: 2 * log2(16) - 1 = 7 stages
    constant BENES_STAGES        : natural := 7;
    constant SWITCHES_PER_STAGE  : natural := BLOCK_WIDTH / 2; -- 8
    constant KEY_WIDTH           : natural := BENES_STAGES * SWITCHES_PER_STAGE; -- 56 bits

    -- =========================================================================
    -- Custom Types & Arrays
    -- =========================================================================
    -- 2D array used to pass signals between pipeline/network stages
    type stage_bus_array is array (natural range <>) of std_logic_vector(BLOCK_WIDTH - 1 downto 0);

    -- State machine states for the migration/control engine
    type controller_state_t is (
        ST_IDLE,
        ST_TRANSLATE,
        ST_MIGRATE_READ,
        ST_MIGRATE_WRITE,
        ST_UPDATE_KEY,
        ST_ERROR
    );

    -- =========================================================================
    -- Function & Procedure Declarations (Prototypes)
    -- =========================================================================
    -- Example utility: computes log2 rounded up (useful for generic sizing)
    function clog2(val : natural) return natural;

end package toplevel_pkg;

-- =============================================================================
-- Package Body: Implementations of Functions / Procedures
-- =============================================================================
package body toplevel_pkg is

    function clog2(val : natural) return natural is
        variable temp : natural := val - 1;
        variable ret  : natural := 0;
    begin
        if val <= 1 then
            return 0;
        end if;
        
        while temp > 0 loop
            temp := temp / 2;
            ret  := ret + 1;
        end loop;
        
        return ret;
    end function clog2;

end package body toplevel_pkg;