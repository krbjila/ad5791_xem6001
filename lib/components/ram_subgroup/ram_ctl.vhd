----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: ram_ctl
-- Project Name: XEM6001 + 6x AD5791
--
-- Controls the ram addresses and enables
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Unsigned and signed
use ieee.numeric_std.all;

-- Typedefs and constants
use work.ad5791_typedefs_constants.all;


entity ram_ctl is
	generic (
		n_channels	: integer; -- number of channels
		depth			: integer; -- 2**depth - 1 is size of RAM
		step_length : integer -- Number of words in a sequence step
	);
	port (
		-- clk, during loading should be USB microcontroller clock from Opal Kelly (ti_clk)
		clk			: in std_logic;
		
		-- Async reset
		rst			: in std_logic;
		
		-- goes high when data is coming from Opal Kelly on ep80pipe
		ep80write	: in std_logic;
		
		-- from computer_ctl.vhd module
		ok_state		: in ok_state_t;
		
		-- from computer_ctl.vhd module
		-- Controls which channel to write to
		channel		: in integer range 0 to n_channels - 1;
		
		-- from dac_interface.vhd module, goes high when ready for new data
		dac_ready	: in std_logic_vector(n_channels - 1 downto 0);
		
		-- control RAM addresses
		address		: out address_t := (others => (others => '0'));
		
		-- ram enables
		en				: out std_logic_vector(n_channels - 1 downto 0) := (others => '0');
		we				: out std_logic_vector(n_channels - 1 downto 0) := (others => '0')
	);
end ram_ctl;

architecture arch_ram_ctl of ram_ctl is

	-- Register for address, which is updated synchronously
	-- en and we are updated asynchronously
	signal a, a_reg : address_t := (others => (others => '0'));
	
	-- ram_hold register is used to avoid giving the dac_interfaces new data too fast.
	-- This is used to ensure that only one new sequence step is sent every time dac_ready goes high
	signal ram_hold, ram_hold_reg : std_logic_vector(n_channels - 1 downto 0) := (others => '0');
	
begin

	-- Registers
	reg : process(clk, rst)
	begin
		if rst = '1' then
			address <= (others => (others => '0'));
			a <= (others => (others => '0'));
			ram_hold <= (others => '0');
		elsif rising_edge(clk) then
			address <= a_reg;
			a <= a_reg;
			ram_hold <= ram_hold_reg;
		end if;
	end process;

	-- Combinational logic controlled by ok_state
	comb : process(ok_state, a, a_reg, ep80write, dac_ready, ram_hold, channel)
	variable hold : std_logic := '0'; -- Counter for holding we high for 1 extra cycle 
	begin
		-- Defaults
		ram_hold_reg <= (others => '0');
		a_reg <= a;
		
		-- Switch on ok_state
		case (ok_state) is
			-- Loading data from computer control
			when ST_LOAD =>
				-- Write enable
				we <= (others => '1');
				
				-- When ep80write goes high, data is coming on ep80pipe
				if ep80write = '1' then
					
					-- Due to timing of ep80write, need to set enable high asynchronously
					for i in 0 to n_channels - 1 loop
						if i = channel then
							en(i) <= '1';
						else
							en(i) <= '0';
						end if;
					end loop;
					
					-- Synchronously update the address
					if a(channel) + 1 < 2**depth - 1 then
						a_reg(channel) <= a(channel) + 1;
					end if;
					
				-- Otherwise, no data is coming
				else
					en <= (others => '0');
				end if;
				
			-- When the sequence is running
			when ST_RUN =>
				-- Enable reading
				we <= (others => '0');
				en <= (others => '1');
				ram_hold_reg <= ram_hold;
				
				-- Update the address if dac_ready is high and ram_hold is low
				-- Requires dac_ready to go low again before the address will be updated the next time
				for i in 0 to n_channels - 1 loop
					if dac_ready(i) = '1' then
						if ram_hold(i) = '0' then
							if a(i) + to_unsigned(step_length, depth) < 2**depth - 1 then
								a_reg(i) <= a(i) + to_unsigned(step_length, depth);
							end if;
							ram_hold_reg(i) <= '1';
						end if;
					else
						ram_hold_reg(i) <= '0';
					end if;
				end loop;
				
			-- When ok_state is ST_IDLE, ST_RESET, ST_INIT
			when others =>
				we <= (others => '0');
				en <= (others => '0');
				a_reg <= (others => (others => '0'));
			end case;	
		end process;

end arch_ram_ctl;

