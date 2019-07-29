----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: dac_interface
-- Project Name: XEM6001 + 6x AD5791
--
-- Controls the serial data to be transmitted with the serial_out.vhd module
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Typedefs and constants
use work.ad5791_typedefs_constants.all;

-- Unsigned and signed
use IEEE.NUMERIC_STD.ALL;
-- or_reduce function
use ieee.std_logic_misc.all;

entity dac_interface is
	generic (
		tw_length : integer; -- Tuning word length in bits (20 for AD5791)
		addr_length : integer; -- Register address length in bits (4 for AD5791)	
		dt_length	: integer; -- Number of bits to define the time between ramp endpoints
		
		-- Ramps are implemented using a phase accumulator
		-- phase_acc_length is the number of extra bits of precision to use to avoid rounding errors
		phase_acc_length : integer;
		-- Min_ramp_dt defines the minimum time of an individual step in the ramp
		-- according to (step time) > 2**min_ramp_dt
		min_ramp_dt		: integer
	);
	port (
		-- Input clock
		-- Clocks synchronous processes and also clocks the serial_out.vhd module
		clk				: in std_logic;
		
		-- State of the Opal Kelly interface, coming from the computer_ctl.vhd module
		ok_state			: in ok_state_t;
		
		-- Data in from the RAM (ram_block.vhd)
		-- data_in defines the next ramp in the sequence
		-- Top dt_length bits are the time interval in units of clk cycles
		-- Remaining bits are the tuning word of the endpoint of the ramp
		data_in			: in std_logic_vector(CONST_N_STEP_WORDS * CONST_STEP_WORD_LENGTH - 1 downto 0);
		
		-- Asynchronous reset
		rst				: in std_logic;
		
		-- Serial data out
		-- Should be attached to the SDIN pin of the AD5791 in the top.vhd module
		sdo				: out std_logic := '0';
		
		-- Sync pin out
		-- Should be attached to the SYNC pin of the AD5791 in the top.vhd module
		-- Since the clk output is always running, sync must be held low for exactly 24 clock falling edges
		-- for a valid data transmission
		sync				: out std_logic := '1';
		
		-- DAC reset pin (inverted, active '0')
		-- Should be attached to the RESET-bar pin of the AD5791 in the top.vhd.module
		inv_dac_rst		: out std_logic := '1';
		
		-- Ready goes high to request new data when the current ramp is finished
		-- Connected to ram_ctl.vhd module
		ready				: out std_logic := '0'
	);
end dac_interface;

architecture arch_dac_interface of dac_interface is

	-- Total serial transmission length
	constant tx_length : integer := tw_length + addr_length;
	-- Latency for triggering serial and receiving "done" signal
	constant SERIAL_LATENCY : integer := 3;
	-- Additional latency of the ST_RUN block due to
	-- calculating ramp parameters
	constant CALCULATION_LATENCY : integer := 4; -- 4 for 1 (ST_NEWDATA) + 1 (ST_PRIORITY) + 1 (ST_CALCULATE) + 1 (ST_ADVANCE)
	-- Total minimum time to output a step on the ramp
	constant MIN_WAIT_TIME : integer := tx_length + SERIAL_LATENCY + CALCULATION_LATENCY;
	-- Wait time difference
	-- Need to account for the data setup, transmission, plus one clock cycle for advance
	constant WAIT_OFFSET : integer := tx_length + SERIAL_LATENCY + 1;

	-- Max wait time for a ramp and max counter value, in clk cycles
	constant MAX_COUNT : integer := 2**dt_length - 1;
	-- RESET_COUNT / 2 is the number of clk cycles to hold inv_dac_rst low
	constant RESET_COUNT : integer := 32;
	-- Counter signal
	signal counter : integer range 0 to max_count := 0;
	
	-- Async reset for serial_out module
	signal serial_rst : std_logic := '0';
	-- serial_trigger goes high to trigger the serial_out module
	-- This output is registered for timing stability
	signal serial_trigger, serial_trigger_reg : std_logic := '0';
	
	-- address and tw are connected to the serial_out module
	-- address controls the register address of serial_out
	-- tw is the tuning word
	signal address : std_logic_vector(addr_length - 1 downto 0) := (others => '0');
	signal tw : std_logic_vector(tw_length - 1 downto 0);
	-- serial_out module outputs done = '1' one clk cycle before sync goes high
	signal done : std_logic;

	-- Registers for calculating ramps.
	-- ramp_time holds the remaining time in the ramp, dt is the time between steps in the ramp.
	-- At each cycle, ramp_time <= ramp_time - dt (roughly). Note that these signals both have an extra phase_acc_length bits of 
	-- precision to avoid rounding errors.
	-- wait_time is the real number of clk cycles to wait between steps in the ramp, after rounding to get an integer
	signal ramp_time, ramp_time_reg, dt, dt_reg : unsigned(dt_length + phase_acc_length - 1 downto 0) := (others => '0');
	signal wait_time, wait_time_reg : unsigned(dt_length - 1 downto 0) := (others => '0');
	
	-- Registers for calculating ramps.
	-- next_voltage holds the final value of the current ramp.
	-- Accumulator hold the current tuning word with phase_acc_length extra bits of precision to avoid rounding errors.
	-- dv holds the tuning word increment at each step in the ramp, also with phase_acc_length extra bits of precision.
	signal next_voltage, next_voltage_reg : std_logic_vector(tw_length - 1 downto 0) := (others => '0');
	signal accumulator, accumulator_reg, dv, dv_reg : signed(tw_length + phase_acc_length - 1 downto 0) := (others => '0');
	
	-- Priority encoder
	-- priority + 1 holds the position of the left-most non-zero value of ramp_time.
	-- This is needed for calculating dt.
	-- If priority - phase_acc_length < min_ramp_dt, then ramp_time is less than the minimum ramp time (2**min_ramp_dt)
	-- so the ramp should just be output as a step.
	-- Otherwise, we can take dt = (ramp_time >> priority + 1 - phase_acc_length - min_ramp_dt),
	-- which gives us 2**(priority - phase_acc_length - min_ramp_dt) steps with very small rounding error (dt has phase_acc_length extra bits of precision)
	signal priority : integer range 0 to dt_length - 1 := 0;

	-- Signal for registering output ready
	signal ready_reg : std_logic := '0';
	
	-- This module is a Moore FSM
	-- State machine typedef
	type dac_state_t is (ST_IDLE, ST_RESET, ST_CLEAR, ST_INIT, ST_INIT_DONE, ST_WAIT, ST_WRITE, ST_NEWDATA, ST_PRIORITY, ST_CALCULATE, ST_ADVANCE);
	-- Previous and next state
	signal pr_state, nx_state : dac_state_t := ST_RESET;
	
begin

	-- Advance state machine
	seq : process(clk, rst) is
	begin
		if rst = '1' then
			pr_state <= ST_RESET;
		elsif rising_edge(clk) then
			pr_state <= nx_state;
		end if;
	end process;
	
	-- Update registers
	reg : process(clk, rst) is
	begin
		if rst = '1' then
			wait_time <= (others => '0');
			next_voltage <= (others => '0');
			ramp_time <= (others => '0');
			accumulator <= (others => '0');
			dv <= (others => '0');
			dt <= (others => '0');
			ready <= '0';
			serial_trigger <= '0';
		elsif rising_edge(clk) then
			wait_time <= wait_time_reg;
			ramp_time <= ramp_time_reg;
			next_voltage <= next_voltage_reg;
			accumulator <= accumulator_reg;
			dt <= dt_reg;
			dv <= dv_reg;
			ready <= ready_reg;
			serial_trigger <= serial_trigger_reg;
		end if;
	end process;
	
	-- Counter used for timing ST_RESET and ST_WAIT
	count : process(clk, rst, pr_state, nx_state, counter) is
	begin
		if rst = '1' then
			counter <= 0;
		elsif rising_edge(clk) then
			if pr_state /= nx_state then
				counter <= 0;
			else
				if counter < max_count then
					counter <= counter + 1;
				else
					counter <= counter;
				end if;
			end if;
		end if;
	end process;
	
	-- Combinational logic for FSM
	comb : process(counter, pr_state, nx_state, ok_state, done, data_in, wait_time, next_voltage, ramp_time, accumulator, dt, dv, priority) is
		variable v1 : unsigned(dt_length + phase_acc_length - 1 downto 0) := (others => '0');
		variable v2 : unsigned(dt_length - 1 downto 0) := (others => '0');
		variable v3 : signed(tw_length + phase_acc_length - 1 downto 0) := (others => '0');
		variable v4 : signed(tw_length downto 0) := (others => '0');
	begin
		-- Assign defaults
		nx_state <= pr_state;
		ready_reg <= '0';
		inv_dac_rst <= '1';
		serial_rst <= '0';
		serial_trigger_reg <= '0';
		address <= CONST_DAC_REG;
		tw <= (others => '0');
		
		-- Assign defaults
		dt_reg <= dt;
		dv_reg <= dv;
		ramp_time_reg <= ramp_time;
		wait_time_reg <= wait_time;
		next_voltage_reg <= next_voltage;
		
		-- Do not clear accumulator_reg in ST_IDLE!
		-- Otherwise the module will not know the current voltage on the DAC
		accumulator_reg <= accumulator;
		
		-- Assign nx_state based on ok_state
		case (ok_state) is
			when ST_RESET =>
				nx_state <= ST_RESET;
			when ST_INIT =>
				nx_state <= ST_CLEAR;
			when ST_RUN =>
				nx_state <= ST_NEWDATA;
			when others =>
				nx_state <= ST_IDLE;
		end case;
	
		-- State machine
		case (pr_state) is
			-- ok_state: ST_IDLE, and others
			when ST_IDLE =>			
				null;
				
			-- ok_state: ST_RESET
			-- Pulse the hardware reset pin on the DAC
			-- Reset the serial_out module
			when ST_RESET =>
				-- Clear current values of ramp accumulator
				accumulator_reg <= (others => '0');
				ramp_time_reg <= (others => '0');
				
				-- Hold down inv_dac_rst
				-- Also reset the serial_out module
				-- Ensure we stay in ST_RESET until this is finished
				if counter < reset_count / 2 then
					inv_dac_rst <= '0';
					serial_rst <= '1';
					nx_state <= ST_RESET;
				elsif counter < reset_count then
					inv_dac_rst <= '1';
					serial_rst <= '0';
					nx_state <= ST_RESET;
				end if;
				
			-- ok_state: ST_INIT
			-- Write all zeros to the DAC
			when ST_CLEAR =>
				-- Write zero to the dac.
				-- Without this step, the dac sometimes outputs VREFN
				-- upon initialization.
				tw <= (others => '0');
				
				-- Clear current values of the ramp accumulator
				accumulator_reg <= (others => '0');
				ramp_time_reg <= (others => '0');
				
				if ok_state = ST_INIT then
					-- If serial_out is not done,
					-- keep the serial trigger high and stay in ST_CLEAR
					if done = '0' then
						serial_trigger_reg <= '1';
						nx_state <= ST_CLEAR;
					-- Otherwise, the serial transmission is finished
					-- Set serial trigger low and go to ST_INIT to write to the control register
					else
						serial_trigger_reg <= '0';
						nx_state <= ST_INIT;
					end if;
				end if;
				
			-- ok_state: ST_INIT
			-- Only comes here after ST_CLEAR
			-- Write to the control register of the DAC
			when ST_INIT =>
				-- Write the initialization code defined in ad5791_typedefs_constants.vhd
				address <= CONST_CTL_REG;
				tw <= CONST_INIT_BITS;
				
				-- Clear current values of the ramp accumulator
				accumulator_reg <= (others => '0');
				ramp_time_reg <= (others => '0');

				if ok_state = ST_INIT then
					-- If serial_out transmission is not done,
					-- set serial_trigger high and stay in ST_INIT
					if done = '0' then
						serial_trigger_reg <= '1';
						nx_state <= ST_INIT;
					-- Otherwise, we can move on to ST_INIT_DONE
					else
						serial_trigger_reg <= '0';
						nx_state <= ST_INIT_DONE;
					end if;
				end if;
			
			-- ok_state: ST_INIT
			-- This state exists so that the ST_CLEAR -> ST_INIT sequence only fires once
			-- instead of indefinitely
			when ST_INIT_DONE =>
				if ok_state = ST_INIT then
					nx_state <= ST_INIT_DONE;
				end if;
				
			-- ok_state: ST_RUN
			-- In the sequence, wait for the next point in the ramp
			when ST_WAIT =>
				-- Wait for wait_time to elapse
				-- MIN_WAIT_TIME counts the latency from ST_NEWDATA, ST_PRIORITY, ST_CALCULATE, and ST_ADVANCE
				-- Subtract 1 because we want to wait exactly wait_time - WAIT_OFFSET total counts,
				-- and counter starts from 0.
				if counter < wait_time - WAIT_OFFSET - 1 then
					if ok_state = ST_RUN then
						nx_state <= ST_WAIT;
					end if;
				else
					if ok_state = ST_RUN then
						nx_state <= ST_WRITE;
					end if;
				end if;
				
			-- ok_state: ST_RUN
			-- Write a value to the DAC
			when ST_WRITE =>
				-- Tuning word is the top tw_length bits of accumulator
				tw <= std_logic_vector(accumulator(accumulator'length - 1 downto phase_acc_length));
				
				-- If not done, stay in ST_RUN
				-- Otherwise, go to ST_ADVANCE
				if done = '0' then
					serial_trigger_reg <= '1';
					nx_state <= ST_WRITE;
				else
					serial_trigger_reg <= '0';
					nx_state <= ST_ADVANCE;
				end if;
				
			-- ok_state: ST_RUN
			-- Calculate the next value to output on the ramp
			-- and the wait_time
			when ST_ADVANCE =>
				-- Move on to ST_NEWDATA
				-- Sending ready high here results in new data coming in from the RAM
				if ramp_time = 0 then
					ready_reg <= '1';
					nx_state <= ST_NEWDATA;
					
				-- Check if ramp_time < 2 * dt to catch remainders
				-- At this point, we really only have one step left in the ramp
				elsif ramp_time < 2 * dt then
					-- Ensure that the final step of the ramp is the correct voltage
					accumulator_reg <= signed(shift_left(resize(unsigned(next_voltage), accumulator'length), phase_acc_length));
					-- Ramp_time will be zero after completing this step
					ramp_time_reg <= (others => '0');
					-- Round down the time remaining in the ramp to get wait_time
					wait_time_reg <= resize(shift_right(ramp_time, phase_acc_length), wait_time'length);
					nx_state <= ST_WAIT;
					
				-- Otherwise, we are in the middle of the ramp
				else
					-- dt would be the wait_time, but we want to avoid rounding errors
					v1 := ramp_time - dt;
					-- The following line rounds to obtain wait_time.
					-- If we think of ramp_time and dt as having decimal parts, then the following line is
					-- floor(ramp_time) - floor(ramp_time - dt)
					v2 := ramp_time(ramp_time'length - 1 downto phase_acc_length) - v1(ramp_time'length - 1 downto phase_acc_length);
					wait_time_reg <= v2;
					-- Update ramp_time
					ramp_time_reg <= v1;
					-- Update dt to account for the inaccuracy in wait_time
					-- Propagate any rounding error to the next time step so that it doesn't accumulate
					dt_reg <= shift_left(dt, 1) - shift_left(resize(v2, ramp_time'length), phase_acc_length);
					
					-- Candidate next voltage step
					v3 := accumulator + dv;
					
					-- Set the next voltage step, unless the next step will overshoot
					accumulator_reg <= v3;
					
					-- Check to avoid overshoot in the ramp
					-- If the ramp is going to overshoot, just set it to the final value
					if (dv > 0) then
						if v3(v3'length - 1 downto phase_acc_length) > signed(next_voltage) then
							accumulator_reg <= signed(shift_left(resize(unsigned(next_voltage), accumulator'length), phase_acc_length));
						end if;
					else
						if v3(v3'length - 1 downto phase_acc_length) < signed(next_voltage) then
							accumulator_reg <= signed(shift_left(resize(unsigned(next_voltage), accumulator'length), phase_acc_length));
						end if;
					end if;
					
					-- Wait before outputting the next voltage step
					nx_state <= ST_WAIT;
				end if;
				
			-- ok_state: ST_RUN
			-- This state occurs at the beginning of the ramp
			-- Calculate dt and dv for the ramp
			when ST_CALCULATE =>	
				-- If the total ramp_time is less than minimum time to output a new voltage,
				-- then we are really outputting a step. Go to the final voltage of the ramp with no wait_time.
				if shift_right(ramp_time, phase_acc_length) < MIN_WAIT_TIME then
					accumulator_reg <= signed(shift_left(resize(unsigned(next_voltage), accumulator'length), phase_acc_length));
					ramp_time_reg <= to_unsigned(0, ramp_time'length);
					
					-- Check to make sure that ok_state is still in ST_RUN.
					-- Otherwise we can miss commands from the computer control if we are outputting voltage steps as fast as possible
					if ok_state = ST_RUN then
						nx_state <= ST_WRITE;
					end if;
					
				-- Otherwise, the total ramp time is long enough to require a wait_time, and possibly multiple voltage steps
				else
					-- (priority + 1) is the position of the left-most nonzero bit of ramp_time
					-- Check to see if the ramp_time is longer than the minimum ramp time (defined by min_ramp_dt).
					-- Need to subtract by phase_acc_length here because ramp_time has an extra phase_acc_length decimal part
					if priority > min_ramp_dt + phase_acc_length then
						-- Then the time step is going to basically be the top min_ramp_dt nonzero bits of ramp_time.
						-- This simplifies the math, as the number of steps in the ramp is now a power of two.
						-- The extra bits of precision in dt and ramp_time ensure that rounding errors are minimal.
						dt_reg <= shift_right(ramp_time, priority - phase_acc_length - min_ramp_dt + 1);
						
						-- The number of voltage steps is given by 2**(priority + 1 - phase_acc_length - min_ramp_dt).
						-- We want to bitshift dv right by the exponent to get the voltage change per step.
						-- Due to the way that dv is calculated in ST_PRIORITY, it also needs to be bit-shifted left by phase_acc_length bits.
						--
						-- We cannot do these two operations sequentially because we will end up rounding unneccessarily.
						-- So do them together at the same time:
						if priority + 1 - phase_acc_length - min_ramp_dt > phase_acc_length then
							dv_reg <= shift_right(dv, (priority - phase_acc_length + 1) - phase_acc_length - min_ramp_dt);
						else
							dv_reg <= shift_left(dv, phase_acc_length + min_ramp_dt - (priority - phase_acc_length + 1));
						end if;
						
					-- Otherwise, the total ramp time is short enough that we should just output a single step.
					-- Note that after the following line is registered,
					-- ramp_time < 2*dt = 2*ramp_time, so we will automatically hit the elsif condition in ST_ADVANCE.
					-- Hence, dv is not needed here.
					else
						dt_reg <= ramp_time;
					end if;
					
					-- If the ramp endpoints are the same value, then just do one long step with no change.
					-- Similarly, remove extra latency:
					if dv = 0 then
						dt_reg <= ramp_time;
					end if;
					
					-- Account for the latency from the calculation stages
					-- 	1 for ST_NEWDATA
					--		1 for ST_PRIORITY
					--		1 for ST_CALCULATE
					--		1 for first ST_ADVANCE
					ramp_time_reg <= ramp_time - shift_left(to_unsigned(CALCULATION_LATENCY, ramp_time'length), phase_acc_length);
						
					-- Go to advance!
					nx_state <= ST_ADVANCE;
				end if;
			
			-- ok_state: ST_RUN
			-- This state happens right after new data comes in.
			-- This is just one clk cycle of latency to allow the priority encoder to function synchronously.
			-- We also start to calculate dv here for convenience.
			when ST_PRIORITY =>
				-- Calculate dv = next_voltage - current_voltage
				-- Note that we have to resize to tw_length + 1 integers here,
				-- as the difference of two N-bit numbers is an (N+1)-bit number.
				-- However, resize pads with zeros or ones to the left, so after this dv will need to be bitshifted left by phase_acc_length bits.
				-- This is done in ST_CALCULATE.
				v4 := resize(signed(next_voltage), tw_length + 1) - resize(accumulator(accumulator'length - 1 downto phase_acc_length), tw_length + 1);
				dv_reg <= resize(v4, dv'length);
				nx_state <= ST_CALCULATE;
				
			-- ok_state: ST_RUN
			-- Waiting for new data.
			when ST_NEWDATA => 
				-- Check to make sure that data is not all zeros.
				-- The end of the sequence coming from the computer must always be padded with lines of all zeros,
				-- otherwise this will not work!
				if or_reduce(data_in) = '1' then				
					-- Set ramp_time to initially be the full ramp time.
					ramp_time_reg <= shift_left(resize(unsigned(data_in(data_in'length - 1 downto tw_length)), ramp_time'length), phase_acc_length);
					-- Next_voltage is set to the final voltage of the ramp.
					next_voltage_reg <= data_in(tw_length - 1 downto 0);
					-- Move on.
					nx_state <= ST_PRIORITY;
				end if;
		end case;
	end process;
	
	-- Priority encoder on ramp_time
	priority_proc : process(clk, rst, ramp_time) is
	begin
		if rst = '1' then
			priority <= 0;
		elsif rising_edge(clk) then
			priority <= 0;
			for i in dt_length - 1 downto 0 loop
				if ramp_time(i) = '1' then
					priority <= i;
					exit;
				end if;
			end loop;
		end if;
	end process;
	
	-- serial_out instance for communication with the DAC
	serial_out_inst : serial_out
	generic map (
		tw_length => tw_length,
		addr_length => addr_length
	)
	port map (
		clk => clk,
		trigger => serial_trigger,
		rst => serial_rst,
		address => address,
		tw	=> tw,
		sync => sync,
		sdo => sdo,
		done => done
	);

end arch_dac_interface;

