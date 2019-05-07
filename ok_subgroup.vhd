----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: ok_subgroup
-- Project Name: XEM6001 + 6x AD5791
--
-- Controls the communication with the computer control via Opal Kelly interface
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Typedefs and constants
use work.ad5791_typedefs_constants.all;

-- Opal Kelly Frontpanel
use work.FRONTPANEL.all;

-- Unsigned and signed
use IEEE.NUMERIC_STD.ALL;

entity ok_subgroup is
	port (
		-- Opal Kelly Interface
		hi_in     	: in    std_logic_vector(7 downto 0);
		hi_out    	: out   std_logic_vector(1 downto 0);
		hi_inout  	: inout std_logic_vector(15 downto 0);
		hi_muxsel 	: out   std_logic;
		
		-- Master reset signal
		-- Connected to ep40trigger(0).
		-- When received in top.vhd, all of the modules in the project get async reset.
		m_rst			: out	  std_logic;
		
		-- Async reset in
		rst			: in std_logic;
		
		trigger		: in std_logic;
		
		-- Clocks
		-- USB clk (ti_clk) from Opal Kelly interface
		clk_out		: out std_logic;
		
		-- State from the computer control,
		-- controlled by ep00wire
		ok_state			: out ok_state_t;
		
		-- Controls which RAM to write to
		channel		: out integer range 0 to CONST_N_CHANNELS - 1 := 0;
		
		-- Pipe in for transferring the sequence into the FPGA
		ep80write	: out std_logic := '0';
		ep80pipe		: out std_logic_vector(15 downto 0)
	);
end ok_subgroup;

architecture arch_ok_subgroup of ok_subgroup is

	-- Clock signals
	signal clk : std_logic := '0';
		
	-- Opal kelly inputs
	signal ep00wire : std_logic_vector(CONST_EP00_N_BITS - 1 downto 0);
	signal ep01wire : std_logic_vector(CONST_EP01_N_BITS - 1 downto 0);
	signal ep40trigger : std_logic_vector(15 downto 0);

begin
	clk_out <= clk;
	m_rst <= ep40trigger(0);
	
	ok_interface_inst : ok_interface
	port map (
		hi_in => hi_in,
		hi_out => hi_out,
		hi_inout => hi_inout,
		hi_muxsel => hi_muxsel,
		rst => rst,
		clk_out => clk,
		ep00wire	=> ep00wire,
		ep01wire	=> ep01wire,
		ep40trigger	=> ep40trigger,
		ep80write => ep80write,
		ep80pipe => ep80pipe
	);
	
	ok_state_ctl_inst : ok_state_ctl
	port map (
		ep00wire => ep00wire,
		ep01wire => ep01wire,
		trigger => trigger,
		rst => rst,
		clk => clk,
		ok_state => ok_state,
		channel => channel
	);
	
end arch_ok_subgroup;

