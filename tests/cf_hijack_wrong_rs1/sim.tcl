# First set this environment variable:
# export MODELSIM_WORKROOT=/tmp (or anywhere you want)

if { [info exists ::env(MODELSIM_WORKROOT)] }   { set MODELSIM_WORKROOT $::env(MODELSIM_WORKROOT)}         else { puts "Please set MODELSIM_WORKROOT environment variable"; exit 1 }

set LIB ${MODELSIM_WORKROOT}/kronos_wrong_reg_bug_

# GUI:
set VOPTARGS "-voptargs=+acc"
set DEBUGDBARG "-debugdb"

# GTKWave:
# set VOPTARGS "-voptargs=-debug"
# set DEBUGDBARG "-debugdb"

rm -rf $LIB

vlog -64 -sv -work $LIB tb_top.sv ../../rtl/core/kronos_types.sv \
                                  ../../rtl/core/kronos_counter64.sv \
                                  ../../rtl/core/kronos_branch.sv \
                                  ../../rtl/core/kronos_alu.sv \
                                  ../../rtl/core/kronos_agu.sv \
                                  ../../rtl/core/kronos_hcu.sv \
                                  ../../rtl/core/kronos_csr.sv \
                                  ../../rtl/core/kronos_lsu.sv \
                                  ../../rtl/core/kronos_RF.sv \
                                  ../../rtl/core/kronos_IF.sv \
                                  ../../rtl/core/kronos_ID.sv \
                                  ../../rtl/core/kronos_EX.sv \
                                  ../../rtl/core/kronos_core.sv

vsim -64 -lib $LIB $DEBUGDBARG $VOPTARGS tb_top

log -r /*
# vcd file sim.vcd
# vcd add -r tb_top/*

do wave.do
restart
run 1000ns