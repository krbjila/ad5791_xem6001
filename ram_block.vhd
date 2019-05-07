----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: ram_block
-- Project Name: XEM6001 + 6x AD5791
--
-- RAM for holding voltage ramp sequence
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Unsigned and signed
use IEEE.NUMERIC_STD.ALL;

entity ram_block is
	generic (
		width 				: integer; -- Word size
		step_length			: integer; -- Length of a single step in the sequence, in words
		depth 				: integer -- 2**depth - 1 is the number of values in the RAM
	);
	port (
		clk		: in std_logic;	-- RAM clk
		en			: in std_logic;	-- enable
		we			: in std_logic;	-- write enable
		address 	: in unsigned(depth - 1 downto 0); -- ram address
		d_in		: in std_logic_vector(width - 1 downto 0); -- data in
		d_out		: out std_logic_vector(width * step_length - 1 downto 0) := (others => '0') -- data out to dac_interface module
	);
end ram_block;

architecture arch_ram_block of ram_block is

	-- Xilinx gives a warning that RAM initialization does not work on Spartan 6
	-- Do not trust the default value of the ram block!
	type ram_block_t is array(2**depth - 1 downto 0) of std_logic_vector(width - 1 downto 0);
	signal ram_block : ram_block_t := (others => (others => '0'));
	

begin
	
	-- Note: Spartan 6 block ram is not compatible with reset
	-- Block ram will not be inferred if we include async reset
	process (clk, address)
	variable a : integer range 0 to 2**depth - 1 := 0;
	begin
		a := to_integer(address);
	
		if rising_edge(clk) then			
			if (en = '1') then
				if (we = '1') then
					-- Write to ram
					ram_block(a) <= d_in;
				end if;
				
				-- Output sequence step
				for i in 0 to step_length - 1 loop
					d_out((i + 1)*width - 1 downto i*width) <= ram_block(a + i);
				end loop;
				
			end if;
		end if;
	end process;

end arch_ram_block;

