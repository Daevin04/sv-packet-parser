# cocotb + Verilator simulation.
#
#   make            run the testbench
#   make SIM=icarus run under Icarus instead (slower, different SV support)
#   make waves      run and dump a VCD to dump.vcd
#   make clean

SIM           ?= verilator
TOPLEVEL_LANG ?= verilog

RTL := $(realpath ..)/rtl

# Order matters: the package must be read before anything that imports it.
VERILOG_SOURCES := \
	$(RTL)/pkt_pkg.sv \
	$(RTL)/frame_parse.sv \
	$(RTL)/resp_gen.sv \
	$(RTL)/parser_top.sv

TOPLEVEL := parser_top
MODULE   := test_parser

# -Wall is deliberate. Lint warnings in RTL are usually real bugs waiting for a
# corner case, and this design is small enough that there is no excuse for any.
EXTRA_ARGS += -Wall

ifneq ($(filter waves,$(MAKECMDGOALS)),)
EXTRA_ARGS += --trace --trace-structs
endif

waves: sim

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves
