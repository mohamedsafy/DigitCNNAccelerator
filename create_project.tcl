# ============================================================================
# ISE 14.7 project creation script for the MNIST CNN accelerator (VHDL only).
#
# Usage: open the "ISE Design Suite 14.7 Command Prompt" (or any shell with
# ISE's settings sourced), cd into this folder, then run:
#       xtclsh create_project.tcl
# and open cnn_mnist.xise in Project Navigator.
#
# Change the target device below to match your board. Defaults: Artix-7 100T
# (Nexys4 / Nexys4 DDR / Arty A7-100), which has 240 DSP48E1 (design uses ~201).
# ============================================================================
set proj_name "cnn_mnist"

set family  "Artix7"
set device  "xc7a100t"
set package "csg324"
set speed   "-1"
# Spartan-6 example (see README: reduce folding for the smaller parts):
# set family "Spartan6"; set device "xc6slx45"; set package "csg324"; set speed "-3"

if {[file exists "$proj_name.xise"]} {
    puts "ERROR: $proj_name.xise already exists - delete it (and the folder's ISE output) first."
    exit 1
}

project new "$proj_name.xise"
project set family  $family
project set device  $device
project set package $package
project set speed   $speed
project set "Preferred Language" "VHDL"
project set "Simulator" "ISim (VHDL/Verilog)"
project set "VHDL Source Analysis Standard" "VHDL-93"

# --- design sources (order: package first) ---------------------------------
foreach f {
    src/cnn_weights_pkg.vhd
    src/swg3x3.vhd
    src/mvau.vhd
    src/maxpool2x2.vhd
    src/fifo.vhd
    src/collect.vhd
    src/argmax.vhd
    src/cnn_top.vhd
    src/cnn_top.ucf
} { xfile add $f }

# --- testbench (simulation view only) --------------------------------------
xfile add "sim/tb_cnn.vhd" -view "Simulation"

project set top "rtl" "cnn_top"

# Optional properties - wrapped in catch so a name mismatch never stops the script.
catch { project set "Simulation Run Time" "all" -process "Simulate Behavioral Model" }
catch { project set "Loop Iteration Limit" "10000" -process "Synthesize - XST" }

project save
project close

# ISim runs in the project folder, so the testbench vectors must be here.
foreach f {images.txt golden_pred.txt labels.txt} {
    file copy -force "sim/$f" "."
}
puts "Created $proj_name.xise - open it in ISE Project Navigator."
