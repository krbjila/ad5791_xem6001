----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    20:22:33 05/07/2019 
-- Design Name: 
-- Module Name:    ok_interface - Behavioral 
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

use work.FRONTPANEL.all;

use work.ad5791_typedefs_constants.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity ok_interface is
	port (
		-- Opal Kelly Interface
		hi_in     	: in    std_logic_vector(7 downto 0);
		hi_out    	: out   std_logic_vector(1 downto 0);
		hi_inout  	: inout std_logic_vector(15 downto 0);
		hi_muxsel 	: out   std_logic;
		
		-- Async reset in
		rst			: in std_logic;
		
		-- Clocks
		-- USB clk (ti_clk) from Opal Kelly interface
		clk_out		: out std_logic;
		
		-- Opal Kelly wires
		ep00wire		: out std_logic_vector(CONST_EP00_N_BITS - 1 downto 0);
		ep01wire		: out std_logic_vector(CONST_EP01_N_BITS - 1  downto 0);
		
		-- Opal Kelly trigger
		ep40trigger	: out std_logic_vector(15 downto 0);
		
		-- Pipe in for transferring the sequence into the FPGA
		ep80write	: out std_logic := '0';
		ep80pipe		: out std_logic_vector(15 downto 0)
	);
end ok_interface;

architecture ok_interface_arch of ok_interface is

	-- Opal Kelly signals
	type ok_record_t is record
		ok1      : std_logic_vector(30 downto 0);
		ok2      : std_logic_vector(16 downto 0);
		ok2s     : std_logic_vector(17*2-1 downto 0);
	end record ok_record_t;
	signal ok : ok_record_t;

	signal clk : std_logic := '0';
	
	signal ep00wire_unsync 	: std_logic_vector(15 downto 0);
	signal ep01wire_unsync	: std_logic_vector(15 downto 0);

begin
	hi_muxsel <= '0';
	clk_out <= clk;
	
	----------------
	-- Opal Kelly --
	----------------

	-- Instantiate the okHost and connect endpoints
	okHI : okHost port map (hi_in=>hi_in, hi_out=>hi_out, hi_inout=>hi_inout, ti_clk=>clk, ok1=>ok.ok1, ok2=>ok.ok2);
	okWO : okWireOR  generic map (N=>2) port map (ok2=>ok.ok2, ok2s=>ok.ok2s);
	ep00 : okWireIn  port map (ok1=>ok.ok1, ep_addr=>x"00", ep_dataout=>ep00wire_unsync);
	ep01 : okWireIn port map (ok1=>ok.ok1, ep_addr=>x"01", ep_dataout=>ep01wire_unsync);
	ep40 : okTriggerIn port map(ok1=>ok.ok1, ep_addr=>x"40", ep_clk=>clk, ep_trigger=>ep40trigger);
	ep80 : okPipeIn  port map (ok1=>ok.ok1, ok2=>ok.ok2s(2*17-1 downto 1*17), ep_addr=>x"80", ep_dataout=>ep80pipe, 
										ep_write=>ep80write);
										
	------------------------
	-- Synchronize inputs --
	------------------------

	sync_inst_ep00wire : synchronizer
	generic map (
		N_BITS => CONST_EP00_N_BITS
	)
	port map (
		clk => clk,
		rst => rst,
		d => ep00wire_unsync(CONST_EP00_N_BITS - 1 downto 0),
		q => ep00wire
	);	

	sync_inst_ep01wire : synchronizer
	generic map (
		N_BITS => CONST_EP01_N_BITS
	)
	port map (
		clk => clk,
		rst => rst,
		d => ep01wire_unsync(CONST_EP01_N_BITS - 1 downto 0),
		q => ep01wire
	);

end ok_interface_arch;

