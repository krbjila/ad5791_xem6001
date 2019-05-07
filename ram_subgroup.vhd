----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    04:25:25 04/27/2019 
-- Design Name: 
-- Module Name:    ram_subgroup - ram_subgroup_arch 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

use work.ad5791_typedefs_constants.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ram_subgroup is
generic (
	n_channels : integer;
	width : integer;
	depth : integer;
	step_length : integer
);
port (
	clk				: in std_logic;
	rst				: in std_logic;
	data_on_pipe 	: in std_logic;
	ok_state			: in ok_state_t;
	channel			: in integer range 0 to n_channels - 1;
	dac_ready		: in std_logic_vector(n_channels - 1 downto 0);
	d_in				: in std_logic_vector(width - 1 downto 0);
	d_out				: out data_in_t
);
end ram_subgroup;

architecture ram_subgroup_arch of ram_subgroup is

	-- RAM enable and address signals
	signal we : std_logic_vector(n_channels - 1 downto 0) := (others => '0');
	signal en : std_logic_vector(n_channels - 1 downto 0) := (others => '0');
	
	signal address : address_t := (others => (others => '0'));

begin

	ram_ctl_inst : ram_ctl
	generic map (
		n_channels => n_channels,
		depth => depth,
		step_length => step_length
	)
	port map (
		clk => clk,
		rst => rst,
		ep80write => data_on_pipe,
		ok_state => ok_state,
		channel => channel,
		dac_ready => dac_ready,
		address => address,
		en => en,
		we => we
	);

	ram_generate : for i in 0 to n_channels - 1 generate
		ram_inst : ram_block
		generic map (
			width 		=> width,
			step_length => step_length,
			depth			=> depth
		)
		port map (
			clk => clk,
			address => address(i),
			en => en(i),
			we => we(i),
			d_in => d_in,
			d_out => d_out(i)
		);
	end generate;

end ram_subgroup_arch;

