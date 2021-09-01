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
		clk_out		: out std_logic;
		global_clk_in : in std_logic;
		
		ok_state_slv	: out std_logic_vector(2 downto 0);
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

	signal clk_sel : std_logic := 0;

	function OKSTATE_TO_SLV(X : ok_state_t)
		return std_logic_vector(2 downto 0) is
	begin
		if X = ST_IDLE then
			return '000';
		elsif X = ST_RESET
			return '001';
		elsif X = ST_INIT
			return '010';
		elsif X = ST_LOAD
			return '011';
		elsif X = ST_READY
			return '100';
		else
			return '101';
		end if;
	end OKSTATE_TO_SLV;

	function SLV_TO_OKSTATE(X : std_logic_vector(2 downto 0))
		return ok_state_t is
	begin
		if X = '000' then
			return ST_IDLE;
		elsif X = '001'
			return ST_RESET;
		elsif X = '010'
			return ST_INIT;
		elsif X = '011'
			return ST_LOAD;
		elsif X = '100'
			return ST_READY;
		else
			return ST_RUN;
		end if;
	end SLV_TO_OKSTATE;
	
begin

	trigger_unsync(0) <= trigger;
	ok_state <= SLV_TO_OKSTATE(ok_state_slv);

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
				if trigger_sync(0) = '1' or pr_state = ST_RUN then
					nx_state <= ST_RUN;
				else
					nx_state <= ST_READY;
				end if;
			when others =>
				nx_state <= ST_IDLE;
		end case;
		
	end process;

	clk_sel <= '1' when (nx_state = ST_READY or nx_state = ST_RUN) else '0';

	sync_out_clk : synchronizer
	generic map (
		N_BITS => 3
	)
	port map (
		clk => clk_out,
		rst => rst,
		d => OKSTATE_TO_SLV(pr_state),
		q => ok_state_slv
	);

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

	BUFGMUX_clk : BUFGMUX
	generic map (
		CLK_SEL_TYPE => "SYNC"  -- Glitchles ("SYNC") or fast ("ASYNC") clock switch-over
	)
	port map (
		O => clk_out,   -- 1-bit output: Clock buffer output
		I0 => clk, -- 1-bit input: Clock buffer input (S=0)
		I1 => ext_clk, -- 1-bit input: Clock buffer input (S=1)
		S => clk_sel    -- 1-bit input: Clock buffer select
	);
	
end ok_state_ctl_arch;

