#!/usr/bin/env python3
# MIT License
# 
# Copyright (c) 2022 Thomas Löcke
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

from os.path import dirname
from pathlib import Path
from vunit import VUnit

test_dir = Path(dirname(__file__))
src_dir = test_dir / ".." / "src"

# setup vunit
ui = VUnit.from_argv()
ui.add_osvvm()
ui.add_com()
ui.add_verification_components()

# add source
src_lib = ui.add_library("axis_rle")
src_lib.add_source_files(src_dir / "*.vhd")

# add tests
test_lib = ui.add_library("tests")
test_lib.add_source_files(test_dir / "*.vhd")

# add configs
tbs = test_lib.get_test_benches()
for tb in tbs:
    tb.add_config(name="S8-C8", generics=dict(SYMBOL_WIDTH=8, COUNTER_WIDTH=8))
    tb.add_config(name="S8-C3", generics=dict(SYMBOL_WIDTH=8, COUNTER_WIDTH=3))

# run
ui.main()
