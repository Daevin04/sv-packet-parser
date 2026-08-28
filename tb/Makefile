# cocotb + Verilator simulation, one example configuration at a time.
#
#   make CONFIG=market       exchange market-data filter  (default)
#   make CONFIG=telemetry    sensor telemetry filter
#   make waves CONFIG=...    same, dumping a VCD
#   make clean

SIM           ?= verilator
TOPLEVEL_LANG ?= verilog
CONFIG        ?= market

RTL := $(realpath ..)/rtl

# Order matters: the package must be read before anything that imports it.
VERILOG_SOURCES := \
	$(RTL)/pkt_pkg.sv \
	$(RTL)/frame_parse.sv \
	$(RTL)/resp_gen.sv \
	$(RTL)/parser_top.sv \
	$(RTL)/examples/$(CONFIG)_filter_top.sv

TOPLEVEL := $(CONFIG)_filter_top
MODULE   := test_$(CONFIG)

# Keep each configuration's build and results separate, so running one does not
# quietly overwrite the other's evidence.
SIM_BUILD    := sim_build_$(CONFIG)
COCOTB_RESULTS_FILE := results_$(CONFIG).xml

# -Wall is deliberate. Lint warnings in RTL are usually real bugs waiting for a
# corner case, and this design is small enough that there is no excuse for any.
EXTRA_ARGS += -Wall

ifneq ($(filter waves,$(MAKECMDGOALS)),)
EXTRA_ARGS += --trace --trace-structs
endif

waves: sim

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves
