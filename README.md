# MNIST CNN accelerator - ISE 14.7 project (VHDL only)

The VHDL design from `demo/manual/`, ported from VHDL-2008 to VHDL-93 so that
XST and ISim in ISE 14.7 accept it. Behaviour is unchanged: verified bit-exact
against the Python golden model (20/20 images, 1,109 cycles/image, same as the
original).

## Folder layout
```
src/   cnn_top.vhd (top), swg3x3, mvau, maxpool2x2, fifo, collect, argmax,
       cnn_weights_pkg.vhd (pre-generated weights), cnn_top.ucf (100 MHz clock)
sim/   tb_cnn.vhd + test vectors (images.txt, golden_pred.txt, labels.txt)
scripts/gen_data_ise.py  regenerates the package / vectors (numpy only)
create_project.tcl       builds the ISE project automatically
```

## Option A - automatic
1. Unzip to a path **without spaces** (e.g. `C:\fpga\cnn_ise`).
2. Edit the device lines at the top of `create_project.tcl` if needed.
3. Start "ISE Design Suite 14.7 Command Prompt", `cd` to the folder, run
   `xtclsh create_project.tcl`, then open `cnn_mnist.xise`.

## Option B - manual (Project Navigator GUI)
1. File > New Project, name `cnn_mnist`, location = this folder, top-level
   source type HDL. Pick your device, Preferred Language = VHDL,
   Simulator = ISim, VHDL Source Analysis Standard = VHDL-93.
2. Project > Add Source: every `.vhd` in `src/` plus `cnn_top.ucf`
   -> association "All" (the UCF: "Implementation").
3. Project > Add Source: `sim/tb_cnn.vhd` -> association "Simulation".
4. Copy `sim/images.txt`, `sim/golden_pred.txt`, `sim/labels.txt` into the
   project folder (next to the .xise) - ISim reads them from there.
5. Right-click `cnn_top` > Set as Top Module.

## Simulation (ISim)
Simulation view > select `tb_cnn` > Simulate Behavioral Model. In the ISim
console type `run all`. Expected output:
```
RTL == golden    : 20 / 20 (bit-exact check)
RTL accuracy     : 95.00 %
latency (img 0)  : 2194 cycles
throughput       : 1109.0 cycles/image
```
More images: `python scripts/gen_data_ise.py 200 0 <mnist_dir>`, copy the
three vector files to the project folder again, and set generic `N` in
`tb_cnn.vhd` to the same number.

## Resources and device choice
Default folding needs about 8k LUT, 10k FF and ~201 DSP multipliers.
- Artix-7 100T (240 DSP) / Zynq 7020 (220 DSP): fits as is.
- Spartan-6 (LX45 = 58 DSP, LX75 = 132, LX150 = 180): XST will build the
  extra multipliers from LUTs. Reduce folding via the `cnn_top` generics,
  e.g. `PE2 => 4, SIMD2 => 4` (Conv2: 16 DSP instead of 128, 8,712
  cycles/image). Rule: PE must divide MH and SIMD must divide MW.

## Using it on a real board
`cnn_top` has a streaming interface (pixel in, class out) and no pin LOCs.
To run on hardware, write a small wrapper that feeds 784 pixels (e.g. from a
BRAM or UART) and drives LEDs / 7-segment with `out_class`, then add the
board's pin LOCs to the UCF.
