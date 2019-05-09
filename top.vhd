----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: top
-- Project Name: XEM6001 + 6x AD5791
--
-- Top level for XEM6001 + 6x AD5791
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Opal Kelly interface
use work.FRONTPANEL.ALL;

-- Typedefs and constants
use work.ad5791_typedefs_constants.all;

-- Unsigned and signed
use IEEE.NUMERIC_STD.ALL;

-- and_reduce
use ieee.std_logic_misc.all;

-- ODDR2
library UNISIM;
use UNISIM.VComponents.all;

entity top is
	port (
      -- Opal Kelly Interface --
		hi_in     			: in    std_logic_vector(7 downto 0);
		hi_out    			: out   std_logic_vector(1 downto 0);
		hi_inout  			: inout std_logic_vector(15 downto 0);
		hi_muxsel 			: out   std_logic;
		led					: out		std_logic_vector(7 downto 0);
		-- External control --
		trigger				: in std_logic;
		m_reset_switch		: in std_logic;
		global_clk_in		: in std_logic;
      -- DAC serial bus --
		sdo_bus 				: out std_logic_vector(CONST_N_CHANNELS - 1 downto 0) := (others => '0');
		sck_bus  			: out std_logic_vector(CONST_N_CHANNELS - 1 downto 0) := (others => '0');
		sync_bus  		  	: out std_logic_vector(CONST_N_CHANNELS - 1 downto 0) := (others => '1');
		reset_inverse_bus	: out std_logic := '1'
    );
end top;

architecture ad5791_board of top is

	-- Clock signals
	signal clk : std_logic := '0';
	
	-- Async reset for all modules
	signal rst : std_logic := '0';

	-- Connects output of RAM to data input of dac_interface
	signal data_in : data_in_t := (others => (others => '0'));
	
	-- Connects ready of dac_interface to dac_ready of ram_ctl
	signal ready : std_logic_vector(CONST_N_CHANNELS - 1 downto 0) := (others => '0');
	
	-- State from computer control 
	signal ok_state : ok_state_t := ST_IDLE;
	-- Master reset signal coming from computer_ctl coming from ep40trigger
	signal m_rst : std_logic := '0';
	
	-- Data transfer signals
	signal ep80write : std_logic := '0';
	signal ep80pipe : std_logic_vector(15 downto 0);
	
	signal channel : integer range 0 to CONST_N_CHANNELS - 1 := 0;

begin
	
	-- Reset all modules
	async_rst : process(m_rst, m_reset_switch)
	begin
		if m_rst = '1' or m_reset_switch = '0' then
			rst <= '1';
		else
			rst <= '0';
		end if;
	end process;
	
	led <= (others => '1');

----------------------
-- Computer control --
----------------------
ok_subgroup_inst : ok_subgroup
port map (
	hi_in => hi_in,
	hi_out => hi_out,
	hi_inout => hi_inout,
	hi_muxsel => hi_muxsel,
	m_rst => m_rst,
	rst => rst,
	trigger => trigger,
	clk_out => clk,
	ok_state => ok_state,
	channel => channel,
	ep80write => ep80write,
	ep80pipe => ep80pipe
);

ram_subgroup_inst : ram_subgroup
generic map (
	n_channels => CONST_N_CHANNELS,
	width => CONST_STEP_WORD_LENGTH,
	depth => CONST_RAM_DEPTH,
	step_length => CONST_N_STEP_WORDS
)
port map (
	clk => clk,
	rst => rst,
	data_on_pipe => ep80write,
	ok_state => ok_state,
	channel => channel,
	dac_ready => ready,
	d_in => ep80pipe,
	d_out => data_in
);


dac_subgroup_inst : dac_subgroup
generic map (
	n_channels => CONST_N_CHANNELS,
	tw_length => CONST_TW_LENGTH,
	addr_length => CONST_ADDR_LENGTH,
	phase_acc_length => CONST_PHASE_ACC_LENGTH,
	min_ramp_dt => CONST_MIN_RAMP_DT,
	dt_length => CONST_DT_LENGTH
)
port map (
	clk => clk,
	ok_state => ok_state,
	data_in => data_in,
	rst => rst,
	sck_bus => sck_bus,
	sdo_bus => sdo_bus,
	sync_bus	=> sync_bus,
	inv_dac_rst_bus => reset_inverse_bus,
	ready => ready
);

end ad5791_board;

