----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: ad5791_typedefs_constants
-- Project Name: XEM6001 + 6x AD5791
--
-- Type definitions and constants.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package ad5791_typedefs_constants is

	----------------------------------
	--- Serial transmit constants ----
	------ Specific to AD5791 --------
	----------------------------------

	--- Word lengths
	constant CONST_ADDR_LENGTH : integer := 4;
	constant CONST_TW_LENGTH : integer := 20;
	
	-- Register addresses
	-- First two bits are always '0'
	constant CONST_DAC_REG : std_logic_vector(CONST_ADDR_LENGTH - 1 downto 0) := "0001";
	constant CONST_CTL_REG : std_logic_vector(CONST_ADDR_LENGTH - 1 downto 0) := "0010";
	
	-- Initialization word
	-- Usings 2s complement, appropriate linearity compensation.
	-- See AD5791 datasheet (page 22) for more details.
	constant CONST_INIT_BITS : std_logic_vector(CONST_TW_LENGTH - 1 downto 0) := "00000000001100100010";
	
	---------------------------------
	---- DAC Interface constants ----
	---------------------------------
	
	
	-- Clock divider
	-- Serial clock is (48 MHz = ti_clk) / CONST_CLK_DIV
	constant CONST_CLK_DIV	: integer := 12;
	
	-- Number of words that define a single step of the sequence
	constant CONST_N_STEP_WORDS : integer := 3;
	-- Number of bits in a word
	constant CONST_STEP_WORD_LENGTH : integer := 16;
	-- Number of bits that define a time interval in the sequence (= 28)
	constant CONST_DT_LENGTH : integer := CONST_N_STEP_WORDS * CONST_STEP_WORD_LENGTH - CONST_TW_LENGTH;

	-- Minimum time for a step in the ramp
	-- Defined as 1 ramp step every  2**CONST_RAMP_STEP_TIME clock cycles
	constant CONST_MIN_RAMP_DT : integer := 6;
	
	-- Number of extra bits on the phase accumulators
	constant CONST_PHASE_ACC_LENGTH : integer := 12;
	
	-- Limit number of steps in a ramp
	-- 2**CONST_MAX_RAMP_STEPS is the max number of steps
	-- Max truncation is 2**(CONST_MAX_RAMP_STEPS - CONST_PHASE_ACC_LENGTH)
	-- So relative to the full scale of the DAC, the maximum rounding error is
	-- 2**(CONST_MAX_RAMP_STEPS - CONST_PHASE_ACC_LENGTH) / 2**(CONST_TW_LENGTH)
	-- For 12 bit phase acc and 2**16 max steps, this gives ~15 ppm max rounding error 
	constant CONST_MAX_RAMP_STEPS : integer := 16;
	

	-----------------------------------
	---- Computer control constant ----
	-----------------------------------
	
	-- Number of bits that define state on ep00wire
	constant CONST_EP00_N_BITS : integer := 3;
	-- Number of bits that define state on ep01wire
	-- This is used for controlling which ram gets written to
	constant CONST_EP01_N_BITS : integer := 3;
	-- ok_state is set by the computer control over ep00wire in the computer_ctl.vhd module
	type ok_state_t is (ST_IDLE, ST_RESET, ST_INIT, ST_LOAD, ST_READY, ST_RUN);


	-------------------------------
	---- Top level constants ------
	-------------------------------
	
	constant CONST_N_CHANNELS : integer := 6;
	constant CONST_RAM_DEPTH : integer := 10;
	
	type address_t is array(CONST_N_CHANNELS - 1 downto 0) of unsigned(CONST_RAM_DEPTH - 1 downto 0);
	type data_in_t is array(CONST_N_CHANNELS - 1 downto 0) of std_logic_vector(CONST_N_STEP_WORDS * CONST_STEP_WORD_LENGTH - 1 downto 0);
	
	--------------------------------------------
	---- ram subgroup component declaration ----
	--------------------------------------------
	
	component ram_subgroup
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
	end component;
	
	component ram_ctl
	generic (
		n_channels	: integer;
		depth 		: integer;
		step_length : integer
	);
	port (
		clk			: in std_logic;
		rst			: in std_logic;
		ep80write	: in std_logic;
		ok_state		: in ok_state_t;
		channel		: in integer;
		dac_ready	: in std_logic_vector(n_channels - 1 downto 0);
		address		: out address_t;
		en				: out std_logic_vector(n_channels - 1 downto 0);
		we				: out std_logic_vector(n_channels - 1 downto 0)
	);
	end component;
	
	component ram_block
	generic (
		width 				: integer;
		step_length			: integer;
		depth 				: integer
	);
	port (
		clk		: in std_logic;
		en			: in std_logic;
		we			: in std_logic;
		address 	: in unsigned(depth - 1 downto 0);
		d_in		: in std_logic_vector(width - 1 downto 0);
		d_out		: out std_logic_vector(width * step_length - 1 downto 0)
	);
	end component;
	
	---------------------------------------------
	---- dac_subgroup component declaration ----
	---------------------------------------------
	
	component dac_subgroup
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
	end component;
	
	component dac_interface
	generic (
		tw_length : integer;
		addr_length : integer;
		phase_acc_length : integer;
		min_ramp_dt		: integer;
		dt_length	: integer;
		max_ramp_steps : integer
	);
	port (
		clk				: in std_logic;
		ok_state			: in ok_state_t;
		data_in			: in std_logic_vector(CONST_N_STEP_WORDS * CONST_STEP_WORD_LENGTH - 1 downto 0);
		rst				: in std_logic;
		sdo				: out std_logic;
		sync				: out std_logic;
		inv_dac_rst		: out std_logic;
		ready				: out std_logic
	);
	end component;
	
	------------------------------------------
	---- serial_out component declaration ----
	------------------------------------------
	
	component serial_out
	generic (
		tw_length 	: integer;
		addr_length	: integer
	);
	port (
		clk 		: in std_logic;
		trigger	: in std_logic;
		rst		: in std_logic;
		address	: in std_logic_vector(addr_length - 1 downto 0);
		tw		 	: in std_logic_vector(tw_length - 1 downto 0);
		sync		: out std_logic;
		sdo		: out std_logic;
		done		: out std_logic
	);
	end component;
	
	
	--------------------------------------------
	---- ok_subgroup component declaration ----
	--------------------------------------------

	component ok_subgroup
	port (
		hi_in     	: in    std_logic_vector(7 downto 0);
		hi_out    	: out   std_logic_vector(1 downto 0);
		hi_inout  	: inout std_logic_vector(15 downto 0);
		hi_muxsel 	: out   std_logic;
		m_rst			: out	  std_logic;
		rst			: in 	std_logic;
		trigger		: in std_logic;
		clk_out		: out std_logic;
		global_clk_in : in std_logic;
		ok_state		: out ok_state_t;
		channel		: out integer range 0 to CONST_N_CHANNELS - 1 := 0;
		ep80write	: out std_logic := '0';
		ep80pipe		: out std_logic_vector(15 downto 0)
	);
	end component;
	
	component ok_interface
	port (
		hi_in     	: in    std_logic_vector(7 downto 0);
		hi_out    	: out   std_logic_vector(1 downto 0);
		hi_inout  	: inout std_logic_vector(15 downto 0);
		hi_muxsel 	: out   std_logic;
		rst			: in std_logic;
		clk_out		: out std_logic;
		ep00wire		: out std_logic_vector(CONST_EP00_N_BITS - 1 downto 0);
		ep01wire		: out std_logic_vector(CONST_EP01_N_BITS - 1  downto 0);
		ep40trigger	: out std_logic_vector(15 downto 0);
		ep80write	: out std_logic := '0';
		ep80pipe		: out std_logic_vector(15 downto 0)
	);
	end component;
	
	component ok_state_ctl
	port (
		ep00wire		: in std_logic_vector(CONST_EP00_N_BITS - 1 downto 0);
		ep01wire		: in std_logic_vector(CONST_EP01_N_BITS - 1 downto 0);
		trigger		: in std_logic;
		rst			: in std_logic;
		clk			: in std_logic;
		clk_out		: out std_logic;
		global_clk_in : in std_logic;
		ok_state		: out ok_state_t;
		channel		: out integer range 0 to CONST_N_CHANNELS - 1
	);
	end component;
	
	--------------------------------------------
	---- synchronizer component declaration ----
	--------------------------------------------
	
	component synchronizer 
	generic (
		N_BITS : integer
	);
	port (
		clk	: in std_logic;
		rst	: in std_logic;
		d		: in std_logic_vector(N_BITS - 1 downto 0);
		q		: out std_logic_vector(N_BITS - 1 downto 0)
	);
	end component;
	
	


end ad5791_typedefs_constants;




package body ad5791_typedefs_constants is
 
end ad5791_typedefs_constants;
