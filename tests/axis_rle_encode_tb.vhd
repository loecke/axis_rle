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

library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.com_context;
context vunit_lib.vc_context;

library osvvm;
use osvvm.RandomBasePkg.all;
use osvvm.RandomPkg.all;

library axis_rle;

entity axis_rle_encode_tb is
  generic(
    SYMBOL_WIDTH  : positive := 8;
    COUNTER_WIDTH : positive := 8;
    runner_cfg    : string
  );
end entity;

architecture tb of axis_rle_encode_tb is
  constant clk_period : time := 10 ns;

  constant axis_input : axi_stream_master_t := new_axi_stream_master(
    data_length  => SYMBOL_WIDTH,
    stall_config => new_stall_config(
      stall_probability => 0.02,
      min_stall_cycles  => 1,
      max_stall_cycles  => 5
    )
  );

  constant axis_output : axi_stream_slave_t := new_axi_stream_slave(
    data_length  => COUNTER_WIDTH + SYMBOL_WIDTH,
    stall_config => new_stall_config(
      stall_probability => 0.02,
      min_stall_cycles  => 1,
      max_stall_cycles  => 5
    )
  );

  signal clk           : std_logic := '0';
  signal rst           : std_logic := '0';
  signal axis_s_tdata  : std_logic_vector(8 * ((SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
  signal axis_s_tvalid : std_logic;
  signal axis_s_tready : std_logic;
  signal axis_s_tlast  : std_logic;
  signal axis_m_tdata  : std_logic_vector(8 * ((COUNTER_WIDTH + SYMBOL_WIDTH + 7) / 8) - 1 downto 0);
  signal axis_m_tvalid : std_logic;
  signal axis_m_tready : std_logic;
  signal axis_m_tlast  : std_logic;

begin
  -- clk generation
  clk <= not clk after clk_period / 2;

  -- dut instantiation
  dut : entity axis_rle.axis_rle_encode
    generic map(
      SYMBOL_WIDTH  => SYMBOL_WIDTH,
      COUNTER_WIDTH => COUNTER_WIDTH
    )
    port map(
      clk           => clk,
      rst           => rst,
      axis_s_tdata  => axis_s_tdata,
      axis_s_tvalid => axis_s_tvalid,
      axis_s_tready => axis_s_tready,
      axis_s_tlast  => axis_s_tlast,
      axis_m_tdata  => axis_m_tdata,
      axis_m_tvalid => axis_m_tvalid,
      axis_m_tready => axis_m_tready,
      axis_m_tlast  => axis_m_tlast
    );

  -- vc input
  vc_input : entity vunit_lib.axi_stream_master
    generic map(
      master => axis_input
    )
    port map(
      aclk     => clk,
      areset_n => not rst,
      tvalid   => axis_s_tvalid,
      tready   => axis_s_tready,
      tdata    => axis_s_tdata(SYMBOL_WIDTH - 1 downto 0),
      tlast    => axis_s_tlast
    );

  -- vc input
  vc_output : entity vunit_lib.axi_stream_slave
    generic map(
      slave => axis_output
    )
    port map(
      aclk     => clk,
      areset_n => not rst,
      tvalid   => axis_m_tvalid,
      tready   => axis_m_tready,
      tdata    => axis_m_tdata(COUNTER_WIDTH + SYMBOL_WIDTH - 1 downto 0),
      tlast    => axis_m_tlast
    );

  -- main test process
  main : process
    variable rnd          : RandomPType;
    variable symbol       : std_logic_vector(SYMBOL_WIDTH - 1 downto 0);
    variable last_symbol  : std_logic_vector(SYMBOL_WIDTH - 1 downto 0);
    variable count        : std_logic_vector(COUNTER_WIDTH - 1 downto 0);
    variable int          : integer;
    variable last         : std_logic;
    variable symbol_count : integer;
    variable q            : queue_t := new_queue;
  begin
    test_runner_setup(runner, runner_cfg);
    rnd.InitSeed(rnd'instance_name);

    -- Put test suite setup code here
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    while test_suite loop

      -- Put common test case setup code here

      if run("test_single_beat_packet") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := (others => '0');
        push_axi_stream(net, axis_input, symbol, '1');
        check_axi_stream(net, axis_output, count & symbol, '1');

      elsif run("test_two_single_beat_packets") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := (others => '0');
        push_axi_stream(net, axis_input, symbol, '1');
        check_axi_stream(net, axis_output, count & symbol, '1');

        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := (others => '0');
        push_axi_stream(net, axis_input, symbol, '1');
        check_axi_stream(net, axis_output, count & symbol, '1');

      elsif run("test_single_symbol_packet") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := rnd.RandSlv(2 ** COUNTER_WIDTH - 2, COUNTER_WIDTH);
        for i in to_integer(unsigned(count)) downto 0 loop
          last := '1' when i = 0 else '0';
          push_axi_stream(net, axis_input, symbol, last);
        end loop;
        check_axi_stream(net, axis_output, count & symbol, '1');

      elsif run("test_single_symbol_packet_max_count") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := (others => '1');
        for i in to_integer(unsigned(count)) downto 0 loop
          last := '1' when i = 0 else '0';
          push_axi_stream(net, axis_input, symbol, last);
        end loop;
        check_axi_stream(net, axis_output, count & symbol, '1');

      elsif run("test_single_symbol_packet_bigger_max_count") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := rnd.RandSlv(COUNTER_WIDTH);
        for i in 2 ** COUNTER_WIDTH + to_integer(unsigned(count)) downto 0 loop
          last := '1' when i = 0 else '0';
          push_axi_stream(net, axis_input, symbol, last);
        end loop;
        check_axi_stream(net, axis_output, (count'range => '1') & symbol, '0');
        check_axi_stream(net, axis_output, count & symbol, '1');
        
      elsif run("test_last_on_new_symbol") then
        symbol := (others => '0');
        count  := rnd.RandSlv(COUNTER_WIDTH);
        for i in to_integer(unsigned(count)) downto 0 loop
          push_axi_stream(net, axis_input, symbol, '0');
        end loop;
        symbol := (others => '1');
        push_axi_stream(net, axis_input, symbol, '1');
        
        symbol := (others => '0');
        check_axi_stream(net, axis_output, count & symbol, '0');
        symbol := (others => '1');
        count := (others => '0');
        check_axi_stream(net, axis_output, count & symbol, '1');
        
      elsif run("test_last_after_full_count") then
        symbol := rnd.RandSlv(SYMBOL_WIDTH);
        count  := (others => '1');
        for i in to_integer(unsigned(count)) downto 0 loop
          push_axi_stream(net, axis_input, symbol, '0');
        end loop;
        push_axi_stream(net, axis_input, symbol, '1');
        
        check_axi_stream(net, axis_output, count & symbol, '0');
        count := (others => '0');
        check_axi_stream(net, axis_output, count & symbol, '1');

      elsif run("test_random_packets") then
        for packet in 9 downto 0 loop
          symbol_count := rnd.RandInt(1, 100);
          report "Sending packet with " & integer'image(symbol_count + 1) & " symbols.";
          for sym in symbol_count - 1 downto 0 loop
            last_symbol := symbol;
            while symbol = last_symbol loop
              symbol := rnd.RandSlv(SYMBOL_WIDTH);
            end loop;
            int         := rnd.FavorSmall(0, 3 * 2 ** COUNTER_WIDTH);
            if rnd.Uniform(0.0, 1.0) < 0.9 then
              int := rnd.FavorSmall(0, 4);
            end if;
            report "Repeating symbol 0x" & to_hex_string(symbol) & " " & integer'image(int + 1) & " times.";
            while int >= 0 loop
              count := std_logic_vector(to_unsigned(int, count'length)) when int < 2 ** COUNTER_WIDTH else (others => '1');
              for i in to_integer(unsigned(count)) downto 0 loop
                last := '1' when int = unsigned(count) and i = 0 and sym = 0 else '0';
                push_axi_stream(net, axis_input, symbol, last);
              end loop;
              push(q, count);
              push(q, symbol);
              push(q, last);
              int   := int - to_integer(unsigned(count)) - 1;
            end loop;
          end loop;
        end loop;

        while not is_empty(q) loop
          count  := pop(q);
          symbol := pop(q);
          last   := pop(q);
          check_axi_stream(net, axis_output, count & symbol, last);
        end loop;
      end if;

      -- Put common test case cleanup code here
      wait until rising_edge(clk);

    end loop;

    -- Put test suite cleanup code here
    test_runner_cleanup(runner);
  end process;

  -- watchdog
  test_runner_watchdog(runner, 500 us);
end architecture tb;
