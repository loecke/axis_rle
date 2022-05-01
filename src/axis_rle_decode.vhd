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

entity axis_rle_decode is
  generic(
    SYMBOL_WIDTH  : positive := 8;
    COUNTER_WIDTH : positive := 8
  );
  port(
    clk           : in  std_logic;
    rst           : in  std_logic;      --

    -- input AXI-Stream
    axis_s_tdata  : in  std_logic_vector(8 * ((COUNTER_WIDTH + SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
    axis_s_tvalid : in  std_logic;
    axis_s_tready : out std_logic;
    axis_s_tlast  : in  std_logic := '1'; --

    -- output AXI-Stream
    axis_m_tdata  : out std_logic_vector(8 * ((SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
    axis_m_tvalid : out std_logic;
    axis_m_tready : in  std_logic;
    axis_m_tlast  : out std_logic := '1'
  );
end entity axis_rle_decode;

architecture arch of axis_rle_decode is

  -- get symbol of encoded data
  function get_symbol(data : std_logic_vector) return std_logic_vector is
  begin
    return data(SYMBOL_WIDTH - 1 downto 0);
  end function get_symbol;

  -- get counter of encoded data
  function get_counter(data : std_logic_vector) return unsigned is
  begin
    return unsigned(data(COUNTER_WIDTH + SYMBOL_WIDTH - 1 downto SYMBOL_WIDTH));
  end function get_counter;

  -- symbol counter
  signal counter : unsigned(COUNTER_WIDTH - 1 downto 0) := (others => '0');

  -- internal data buffer
  signal axis_int_tdata  : std_logic_vector(axis_s_tdata'range);
  signal axis_int_tvalid : std_logic := '0';
  signal axis_int_tlast  : std_logic;

  -- tlast to be set on symbol end
  signal axis_m_tlast_pending : std_logic;

begin

  -- decode data process
  decode_proc : process(clk) is
  begin
    if rising_edge(clk) then
      -- input tready signaling
      axis_s_tready <= '1';
      if axis_int_tvalid = '1' then
        axis_s_tready <= '0';
      end if;

      -- output AXI handshake
      if axis_m_tready = '1' then
        axis_m_tvalid <= '0';
      end if;

      -- input AXI handshake
      if axis_s_tvalid = '1' and axis_s_tready = '1' then
        axis_s_tready   <= '0';
        axis_int_tdata  <= axis_s_tdata;
        axis_int_tlast  <= axis_s_tlast;
        axis_int_tvalid <= '1';
      end if;

      -- can set new data
      if axis_m_tready = '1' or axis_m_tvalid = '0' then
        -- repeat symbol
        if counter > 0 then
          axis_m_tvalid <= '1';
          if counter = 1 then
            axis_m_tlast <= axis_m_tlast_pending;
          end if;
          counter       <= counter - 1;

        -- start symbol from internal buffer
        elsif axis_int_tvalid = '1' then
          axis_m_tdata(SYMBOL_WIDTH - 1 downto 0) <= get_symbol(axis_int_tdata);
          axis_m_tlast                            <= axis_int_tlast;
          axis_m_tvalid                           <= '1';

          axis_m_tlast_pending <= '0';
          counter              <= get_counter(axis_int_tdata);
          if get_counter(axis_int_tdata) > 0 then
            axis_m_tlast         <= '0';
            axis_m_tlast_pending <= axis_int_tlast;
          end if;

          axis_s_tready   <= '1';
          axis_int_tvalid <= '0';
          if axis_s_tvalid = '1' and axis_s_tready = '1' then
            axis_s_tready   <= '0';
            axis_int_tvalid <= '1';
          end if;

        -- start symbol from input
        elsif axis_s_tvalid = '1' and axis_s_tready = '1' then
          axis_m_tdata(SYMBOL_WIDTH - 1 downto 0) <= get_symbol(axis_s_tdata);
          axis_m_tlast                            <= axis_s_tlast;
          axis_m_tvalid                           <= '1';

          axis_m_tlast_pending <= '0';
          counter              <= get_counter(axis_s_tdata);
          if get_counter(axis_s_tdata) > 0 then
            axis_m_tlast         <= '0';
            axis_m_tlast_pending <= axis_s_tlast;
          end if;

          axis_s_tready   <= '1';
          axis_int_tvalid <= '0';
        end if;
      end if;

      -- reset
      if rst = '1' then
        axis_s_tready   <= '0';
        axis_m_tvalid   <= '0';
        axis_int_tvalid <= '0';
        counter         <= (others => '0');
      end if;
    end if;
  end process decode_proc;

end architecture arch;
