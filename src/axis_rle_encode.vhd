--MIT License
--
--Copyright (c) 2022 Thomas Löcke
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_rle_encode is
  generic(
    SYMBOL_WIDTH  : positive := 8;
    COUNTER_WIDTH : positive := 8
  );
  port(
    clk           : in  std_logic;
    rst           : in  std_logic;      --

    -- input AXI-Stream
    axis_s_tdata  : in  std_logic_vector(8 * ((SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
    axis_s_tvalid : in  std_logic;
    axis_s_tready : out std_logic;
    axis_s_tlast  : in  std_logic := '1'; --

    -- output AXI-Stream
    axis_m_tdata  : out std_logic_vector(8 * ((COUNTER_WIDTH + SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
    axis_m_tvalid : out std_logic;
    axis_m_tready : in  std_logic;
    axis_m_tlast  : out std_logic := '1'
  );
end entity axis_rle_encode;

architecture arch of axis_rle_encode is

  -- internal stream
  signal data  : std_logic_vector(SYMBOL_WIDTH - 1 downto 0);
  signal valid : std_logic := '0';
  signal ready : std_logic;
  signal last  : std_logic;
  signal equal : std_logic;

  -- output process data
  signal data_old      : std_logic_vector(SYMBOL_WIDTH - 1 downto 0);
  signal counter       : unsigned(COUNTER_WIDTH - 1 downto 0);
  signal counter_valid : std_logic := '0';
  signal counter_high  : std_logic;
  signal data_out      : std_logic_vector(COUNTER_WIDTH + SYMBOL_WIDTH - 1 downto 0);
  signal pending_last  : std_logic := '0';

begin

  -- set input ready when data can be forwarded to internal stream
  axis_s_tready <= (ready and not pending_last) or not valid;

  -- set internal ready when data can be forwarded to output and no old data has to be forwarded first
  ready <= (axis_m_tready or not axis_m_tvalid) and (not last or not counter_valid or equal);

  -- set all relevant output data bits
  axis_m_tdata(COUNTER_WIDTH + SYMBOL_WIDTH - 1 downto 0) <= data_out;

  -- forward input to internal stream and add equal information
  compare_proc : process(clk) is
  begin
    if rising_edge(clk) then
      -- AXI handshake
      if ready = '1' then
        valid <= '0';
      end if;

      -- can set new data and new data available
      if (valid = '0' or ready = '1') and axis_s_tvalid = '1' then
        data  <= axis_s_tdata(SYMBOL_WIDTH - 1 downto 0);
        valid <= '1';
        last  <= axis_s_tlast;
        equal <= '0';
        if axis_s_tdata(SYMBOL_WIDTH - 1 downto 0) = data then
          equal <= '1';
        end if;
      end if;

      -- reset
      if rst = '1' then
        valid <= '0';
      end if;
    end if;
  end process compare_proc;

  -- count equal symbols and set output
  count_proc : process(clk) is
  begin
    if rising_edge(clk) then
      -- output AXI handshake
      if axis_m_tready = '1' then
        axis_m_tvalid <= '0';
      end if;

      -- can set new data
      if axis_m_tvalid = '0' or axis_m_tready = '1' then
        pending_last <= '0';

        -- pending last must be send
        if pending_last = '1' then
          data_out      <= std_logic_vector(counter) & data;
          axis_m_tlast  <= '0';
          axis_m_tvalid <= '1';
          axis_m_tlast  <= '1';

        -- new data is available
        elsif valid = '1' then
          -- process new data
          data_old      <= data;
          counter_valid <= not last;
          if equal = '1' then
            counter <= counter + 1;
          end if;
          if equal = '0' or counter_valid = '0' then
            counter <= (others => '0');
          end if;
          if counter = 2 ** COUNTER_WIDTH - 2 then
            counter_high  <= counter_valid;
          else
            counter_high <= '0';
          end if;

          -- check for last on new symbol
          if counter_valid = '0' then
            if last = '1' then
              data_out      <= (counter'range => '0') & data;
              axis_m_tlast  <= '1';
              axis_m_tvalid <= '1';
            end if;
          else
            -- check for new symbol
            if equal = '0' then
              data_out      <= std_logic_vector(counter) & data_old;
              axis_m_tlast  <= '0';
              axis_m_tvalid <= '1';
              counter_high  <= '0';
            -- check for counter overflow
            elsif counter_high = '1' then
              data_out      <= std_logic_vector(counter) & data;
              axis_m_tlast  <= '0';
              axis_m_tvalid <= '1';
              if last = '1' then
                pending_last <= '1';
              end if;
            -- check for last
            elsif last = '1' then
              data_out      <= std_logic_vector(counter + 1) & data;
              axis_m_tlast  <= last;
              axis_m_tvalid <= '1';
            end if;
          end if;
        end if;
      end if;

      -- reset
      if rst = '1' then
        axis_m_tvalid <= '0';
        counter_valid <= '0';
        pending_last  <= '0';
      end if;
    end if;
  end process count_proc;

end architecture arch;
