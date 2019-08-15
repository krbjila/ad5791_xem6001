----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    04:00:16 04/27/2019 
-- Design Name: 
-- Module Name:    dac_subgroup - dac_subgroup_arch 
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

use IEEE.NUMERIC_STD.ALL;

use work.ad5791_typedefs_constants.all;

-- and_reduce
use ieee.std_logic_misc.all;

library UNISIM;
use UNISIM.VComponents.all;

entity dac_subgroup is
generic (
	n_channels : integer;
	tw_length : integer;
	addr_length : integer;
	phase_acc_length : integer;
	min_ramp_dt		: integer;
	dt_length	: integer;
	max_ramp_steps : integer
);
port (
	clk					: in std_logic;
	ok_state				: in ok_state_t;
	data_in				: in data_in_t;
	rst					: in std_logic;
	sck_bus				: out std_logic_vector(n_channels - 1 downto 0);
	sdo_bus				: out std_logic_vector(n_channels - 1 downto 0);
	sync_bus				: out std_logic_vector(n_channels - 1 downto 0);
	inv_dac_rst_bus	: out std_logic;
	ready					: out std_logic_vector(n_channels - 1 downto 0)
);
end dac_subgroup;

architecture dac_subgroup_arch of dac_subgroup is

	signal dac_clk, dac_clk_unbuffered : std_logic := '0';
	signal dac_clk_inv, dac_clk_inv_unbuffered : std_logic := '1';
	
	signal inv_dac_rst : std_logic_vector(n_channels - 1 downto 0) := (others => '0');
	
	signal ok_state_sync, ok_state_temp : ok_state_t;
	
	attribute ASYNC_REG : string;
	attribute RLOC : string;
	
	attribute ASYNC_REG of ok_state_temp : signal is "TRUE";
	attribute ASYNC_REG of ok_state_sync : signal is "TRUE";

begin

	inv_dac_rst_bus <= and_reduce(inv_dac_rst);
	
	dac_generate : for i in 0 to n_channels - 1 generate
		dac_inst_0 : dac_interface
		generic map (
			tw_length => tw_length,
			addr_length => addr_length,
			phase_acc_length => phase_acc_length,
			min_ramp_dt => min_ramp_dt,
			dt_length => dt_length,
			max_ramp_steps => max_ramp_steps
		)
		port map (
			clk => dac_clk,
			ok_state => ok_state_sync,
			data_in => data_in(i),
			rst => rst,
			sdo => sdo_bus(i),
			sync => sync_bus(i),
			inv_dac_rst => inv_dac_rst(i),
			ready => ready(i)
		);
	end generate;
	
	dac_clk_divider : process(clk, rst) is
	variable x : integer range 0 to CONST_CLK_DIV - 1;
	begin
		if rst = '1' then
			dac_clk_unbuffered <= '0';
			dac_clk_inv_unbuffered <= '1';
			x := 0;
		elsif rising_edge(clk) then
			if x < CONST_CLK_DIV / 2 then
				dac_clk_unbuffered <= '0';
				dac_clk_inv_unbuffered <= '1';
				x := x + 1;
			elsif x < CONST_CLK_DIV - 1 then
				dac_clk_unbuffered <= '1';
				dac_clk_inv_unbuffered <= '0';
				x := x + 1;
			else
				dac_clk_unbuffered <= '1';
				dac_clk_inv_unbuffered <= '0';
				x := 0;
			end if;
		end if;
	end process;


	-- ODDR2: Output Double Data Rate Output Register with Set, Reset
	--        and Clock Enable. 
	--        Spartan-6
	-- Xilinx HDL Language Template, version 14.7
	sck_out_generate : for i in 0 to n_channels - 1 generate	
		ODDR2_inst : ODDR2
		generic map(
			DDR_ALIGNMENT => "NONE", -- Sets output alignment to "NONE", "C0", "C1" 
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => sck_bus(i), -- 1-bit output data
			C0 => dac_clk, -- 1-bit clock input
			C1 => dac_clk_inv, -- 1-bit clock input
			CE => '1',  -- 1-bit clock enable input
			D0 => '1',   -- 1-bit data input (associated with C0)
			D1 => '0',   -- 1-bit data input (associated with C1)
			R => rst,    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);
	end generate;

	BUFG_inst_0 : BUFG
   port map (
      I => dac_clk_unbuffered, -- 1-bit output: Clock buffer output
      O => dac_clk -- 1-bit input: Clock buffer input
   );
	
	BUFG_inst_1 : BUFG
   port map (
      I => dac_clk_inv_unbuffered, -- 1-bit output: Clock buffer output
      O => dac_clk_inv  -- 1-bit input: Clock buffer input
   );

	
	sync_ok_state : process(dac_clk, ok_state, ok_state_sync, ok_state_temp) is 
	begin
		if rising_edge(dac_clk) then
			ok_state_temp <= ok_state;
			ok_state_sync <= ok_state_temp;
		end if;
	end process;
	
	
end dac_subgroup_arch;

