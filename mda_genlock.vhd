-- MDA Genlock
-- 2017 Luis Antoniosi

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mda_genlock is

    port(	
		clk 					: in std_logic;
		enable				: in std_logic;			
		vblank  				: in std_logic; 
		hblank 				: in std_logic;						
		video					: in std_logic;
		intensity			: in std_logic;
		wr_ack				: in std_logic;
		col_number			: buffer unsigned(9 downto 0); 
		row_number			: buffer unsigned(9 downto 0); 			
		wren					: out std_logic;
		wr_req				: buffer std_logic;
		pixel					: out unsigned(5 downto 0);
		sram_clk				: in std_logic;
		adjust_x				: buffer unsigned(4 downto 0);
		adjust_y				: buffer unsigned(4 downto 0);
		vsync					: in std_logic;
		hsync					: in std_logic;
		max_col				: out unsigned(9 downto 0);
		max_row				: out unsigned(9 downto 0);
		
		samples				: in unsigned(2 downto 0);
		top_border			: in unsigned(7 downto 0);
		left_border 		: in unsigned(7 downto 0);
		r  					: in std_logic;
		g   					: in std_logic;
		b  					: in std_logic		
);
			
end mda_genlock;

architecture behavioral of mda_genlock is

constant c_capture_total_cols	: integer := 410;
constant c_capture_active_cols	: integer := 320;
constant c_capture_active_rows	: integer := 240;
constant c_default_line_ticks	: integer := 1854;

signal hcount			 : unsigned (13 downto 0); 
signal vcount			 : unsigned (13 downto 0); 
signal vi	 			 : unsigned (1 downto 0);
signal store_trg		 : std_logic := '0';

signal s_col_begin	: integer range 0 to 2048 := 0;
signal s_col_end		: integer range 0 to 2048 := c_capture_active_cols;
signal s_row_begin	: integer range 0 to 2048 := 0;
signal s_row_end		: integer range 0 to 2048 := c_capture_active_rows;
signal line_ticks		: integer range 1 to 4095 := c_default_line_ticks;
signal sample_accum	: integer range 0 to 8191 := 0;
signal sample_col		: integer range 0 to 2048 := 0;

begin

	process(clk, enable, samples, left_border, top_border)
	begin
		if (rising_edge(clk)) then	
			if (enable = '1') then
				s_col_begin <= to_integer(left_border);
				s_col_end <= to_integer(left_border) + c_capture_active_cols;
				s_row_begin <= to_integer(top_border);
				s_row_end <= to_integer(top_border) + c_capture_active_rows;
			end if;
		end if;
	end process;	

	-- colum counter
	process(clk, hblank, enable)
	begin		
		if (rising_edge(clk)) then
			if (enable = '1') then
				if (hblank = '1') then
					max_col <= col_number + 1;
					if (col_number >= 807) then
						max_col <= to_unsigned(807, max_col'length);
					end if;						
					hcount <= (others => '0');
				else
					hcount <= hcount + 1;					
				end if;				
			end if;
		end if;		
	end process;

	process(clk, hblank, enable)
	begin
		if (rising_edge(clk)) then
			if (enable = '1') then
				if (hblank = '1' and hcount > 0) then
					line_ticks <= to_integer(hcount);
				end if;
			end if;
		end if;
	end process;

	-- line counter
	process(clk, hblank, vblank, enable)
	begin
		if (rising_edge(clk)) then
			if (enable = '1') then
				if (hblank = '1') then				
					vcount <= vcount + 1;
				elsif (vblank = '1') then
					max_row <= row_number + 1;
					vcount <= (others => '0');
				end if;
			end if;
		end if;
	end process;

	-- sram sync
	process(sram_clk, hcount, hblank, wr_ack)
	begin
		if (wr_ack = '1') then
			wr_req <= '0';
		elsif (rising_edge(sram_clk)) then
			if (store_trg = '1') then
				wr_req <= '1'; -- dispatch row to SRAM
			end if;
		end if;
	end process;

	-- resample the source line to a fixed 320 pixel raster using the measured line length
	process(clk, enable, hblank, video, intensity, s_col_begin, s_col_end, s_row_begin, s_row_end)
	variable next_accum	: integer range 0 to 8191;
	variable sample_now	: std_logic;
	variable mono_video	: std_logic;
	variable mono_intensity	: std_logic;
	begin	
		if (rising_edge(clk)) then		
			if (enable = '1') then
				wren <= '0';
				sample_now := '0';

				if (hblank = '1') then
					sample_accum <= 0;
					sample_col <= 0;
					col_number <= (others => '0');
				elsif (sample_col < c_capture_total_cols) then
					next_accum := sample_accum + c_capture_total_cols;
					if (next_accum >= line_ticks) then
						sample_accum <= next_accum - line_ticks;
						sample_col <= sample_col + 1;
						sample_now := '1';
					else
						sample_accum <= next_accum;
					end if;
				end if;

				if (sample_now = '1') then
					if (sample_col > s_col_begin and sample_col < s_col_end and vcount > s_row_begin and vcount < s_row_end) then
						mono_video := not video;
						mono_intensity := '0';
						wren <= '1'; -- enable row RAM write
						col_number <= col_number + 1;
						pixel <= mono_video & mono_intensity & mono_video & mono_intensity & mono_video & mono_intensity;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	process(clk, vcount, hblank, s_row_begin, s_row_end, enable)
	begin		
		if (rising_edge(clk)) then		
			if (enable = '1') then
				if (wr_req = '1') then
					store_trg <= '0';
				end if;
				
				if (hblank = '1') then			
					if (vcount > s_row_begin and vcount < s_row_end) then
						row_number <= row_number + 1;		
						store_trg <= '1';
					end if;				
				end if;
				
				if (vblank = '1') then				
					row_number <= (others => '0');				
				end if;
			end if;
		end if;
	end process;

end behavioral;
