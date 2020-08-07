----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    20:22:49 05/07/2019 
-- Design Name: 
-- Module Name:    ok_state_ctl - Behavioral 
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

use work.ad5791_typedefs_constants.all;

use IEEE.NUMERIC_STD.ALL;

entity ok_state_ctl is
	port (
		ep00wire		: in std_logic_vector(CONST_EP00_N_BITS - 1 downto 0);
		ep01wire		: in std_logic_vector(CONST_EP01_N_BITS - 1 downto 0);
		trigger		: in std_logic; -- hardware trigger
		
		rst			: in std_logic;
		
		clk			: in std_logic;
		
		ok_state		: out ok_state_t;
		channel		: out integer range 0 to CONST_N_CHANNELS - 1
	);
end ok_state_ctl;

architecture ok_state_ctl_arch of ok_state_ctl is
	
	-- State machine for ep00wire state
	signal nx_state, pr_state : ok_state_t := ST_IDLE;
	
	signal trigger_unsync : std_logic_vector(0 downto 0) := (others => '0');
	signal trigger_sync : std_logic_vector(0 downto 0) := (others => '0');
	signal channel_reg : integer range 0 to CONST_N_CHANNELS - 1 := 0;
	
begin

	trigger_unsync(0) <= trigger;
	ok_state <= pr_state;

	-- Advance state
	seq : process(clk, rst) is
	begin
		if rst = '1' then
			pr_state <= ST_IDLE;
			channel <= 0;
		elsif rising_edge(clk) then
			pr_state <= nx_state;
			channel <= channel_reg;
		end if;
	end process;
	
	-- State machine
	-- Control ok_state for various components
	comb : process(nx_state, pr_state, ep00wire, ep01wire, trigger_sync) is
	begin
		-- Convert ep01wire to integer to get channel
		-- This is used to select the channel to write to in RAM
		channel_reg <= to_integer(unsigned(ep01wire));
		
		-- Default ok_state control
		case ep00wire is
			when "000" =>
				nx_state <= ST_IDLE;
			when "001" =>
				nx_state <= ST_RESET;
			when "010" =>
				nx_state <= ST_INIT;
			when "011" =>
				nx_state <= ST_LOAD;
			when "100" =>
				-- Trigger goes high to start sequence
				-- 8/7/20 added optoisolator in trigger line
				-- This inverts the trigger
				if trigger_sync(0) = '0' or pr_state = ST_RUN then
					nx_state <= ST_RUN;
				else
					nx_state <= ST_READY;
				end if;
			when others =>
				nx_state <= ST_IDLE;
		end case;
		
	end process;

	sync_inst_trigger : synchronizer
	generic map (
		N_BITS => 1
	)
	port map (
		clk => clk,
		rst => rst,
		d => trigger_unsync,
		q => trigger_sync
	);
	
end ok_state_ctl_arch;

