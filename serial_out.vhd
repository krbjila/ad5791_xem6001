----------------------------------------------------------------------------------
-- JILA KRb
-- Kyle Matsuda 
-- April 2019
--
-- Module Name: serial_out
-- Project Name: XEM6001 + 6x AD5791
--
-- Shifts out serial data.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity serial_out is
	generic (
		tw_length 	: integer; -- Tuning word length (20 for AD5791)
		addr_length	: integer -- Address word length (4 for AD5791)
	);
	port (
		-- Serial clock, should be same as what's going to the SCK pin on AD5791
		clk 		: in std_logic;
		
		-- When trigger goes high, address & tw is latched in and data is shifted out on sdo port
		trigger	: in std_logic;
		
		-- Async reset
		rst		: in std_logic;
		
		-- Address word for targeting AD5791 registers
		address	: in std_logic_vector(addr_length - 1 downto 0);
		
		-- Tuning word
		tw		 	: in std_logic_vector(tw_length - 1 downto 0);
		
		-- Sync
		-- Should be connected to sync pin on top module
		-- Since clk is never idle, sync must go low for exactly 24 clock falling edges
		-- for valid data trasmission.
		sync		: out std_logic := '1';
		
		-- Data out pin
		-- Should be connected to sdo pin on top module
		sdo		: out std_logic := '0';
		
		-- Done goes high for 1 clock cycle as the last bit is being shifted out
		done		: out std_logic := '0'
	);
end serial_out;

architecture arch_serial of serial_out is

	-- Moore FSM
	-- Define state and state signals
	type serial_state_t is (ST_IDLE, ST_TX, ST_DONE);
	signal pr_state, nx_state : serial_state_t := ST_IDLE;
	
	-- Registers for done, sync, sdo
	signal done_reg, sdo_reg : std_logic := '0';
	signal sync_reg : std_logic := '1';
	
	attribute iob : string;
	attribute iob of sdo, sync : signal is "TRUE";
	
	-- tx_length is the length of a transmission in bits or clock cycles
	-- Counter is used to step through the output array
	constant tx_length : integer := tw_length + addr_length;
	signal counter : integer range 0 to tx_length - 1 := 0;
		
	signal t, t_reg : std_logic_vector(tw_length - 1 downto 0) := (others => '0');
	
begin
	
	-- Advance state
	seq : process(clk, rst) is
	begin
		if rst = '1' then
			pr_state <= ST_IDLE;
		elsif rising_edge(clk) then
			pr_state <= nx_state;
		end if;
	end process;
	
	-- Register outputs
	reg : process(clk, rst) is
	begin
		if rst = '1' then
			sync <= '1';
			sdo <= '0';
			done <= '0';
			t <= (others => '0');
		elsif rising_edge(clk) then
			sync <= sync_reg;
			sdo <= sdo_reg;
			done <= done_reg;
			t <= t_reg;
		end if;
	end process;
	
	-- Counter
	count : process(clk, rst, pr_state, nx_state) is
	begin
		if rst = '1' then
			counter <= 0;
		elsif rising_edge(clk) then
			if pr_state /= nx_state then
				counter <= 0;
			else
				if counter < tx_length - 1 then
					counter <= counter + 1;
				else
					counter <= 0;
				end if;
			end if;
		end if;
	end process;
	
	
	-- Combinational logic for FSM
	comb : process(trigger, address, tw, counter, pr_state, nx_state, t) is
	variable x : std_logic_vector(tx_length - 1 downto 0) := (others => '0');
	begin
		-- Set defaults
		nx_state <= pr_state;
		done_reg <= '0';
		sync_reg <= '1';
		sdo_reg <= '0';
		t_reg <= t;
		x := (others => '0');
		
		-- State machine
		case(pr_state) is
			-- Idle state
			when ST_IDLE =>
				
				-- When triggered, latch data and prepare to transmit
				if trigger = '1' then
					nx_state <= ST_TX;					
					t_reg <= tw;
				end if;
				
			-- Trasmitting data
			when ST_TX =>
				-- Pull sync low to transmit
				sync_reg <= '0';
				x := address & t;
				sdo_reg <= x(x'length - 1 - counter);
				
				-- When done, pull done high and go to ST_DONE
				if counter < tx_length - 1 then
					nx_state <= ST_TX;
				else
					done_reg <= '1';
					nx_state <= ST_DONE;
				end if;
			
			-- Wait for trigger to go low before going back to ST_IDLE
			when ST_DONE =>
				if trigger = '0' then
					nx_state <= ST_IDLE;
				end if;

		end case;
	end process;
	
end arch_serial;

