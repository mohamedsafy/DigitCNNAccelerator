-- ============================================================================
-- MANUAL design: layer-pipelined streaming (dataflow) accelerator for the
-- seminar's MNIST CNN. Folding exactly as in the script's DSE table:
--     Conv1 : PE=8 , SIMD=9  ->  72 MAC/cycle,   1 cycle/pixel x 676 = 676
--     Conv2 : PE=16, SIMD=8  -> 128 MAC/cycle,   9 cycle/pixel x 121 = 1089
--     Dense : PE=1 , SIMD=4  ->   4 MAC/cycle, 1000 cycle/image
--  in (1 px/beat) -> SWG1 -> MVAU1(+ReLU) -> Pool1 -> FIFO -> SWG2
--     -> MVAU2(+ReLU) -> Pool2 -> Flatten -> MVAU3 -> argmax -> class
-- All layers run concurrently; the slowest stage (Conv2) sets the throughput.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use work.cnn_weights_pkg.all;

entity cnn_top is
  generic (
    PE1 : positive := 8;  SIMD1 : positive := 9;
    PE2 : positive := 16; SIMD2 : positive := 8;
    PE3 : positive := 1;  SIMD3 : positive := 4;
    FIFO_DEPTH : natural := 32);          -- pool1 -> swg2 decoupling FIFO (0 = none)
  port (
    clk, rst  : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_pixel  : in  std_logic_vector(7 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_class : out std_logic_vector(3 downto 0));
end entity;

architecture rtl of cnn_top is
  signal w1_v, w1_r, c1_v, c1_r, p1_v, p1_r, q1_v, q1_r : std_logic;
  signal w2_v, w2_r, c2_v, c2_r, p2_v, p2_r, f_v, f_r   : std_logic;
  signal w1_d   : std_logic_vector(9*8-1 downto 0);
  signal c1_d, p1_d, q1_d : std_logic_vector(8*8-1 downto 0);
  signal w2_d   : std_logic_vector(9*8*8-1 downto 0);
  signal c2_d, p2_d : std_logic_vector(16*8-1 downto 0);
  signal f_d    : std_logic_vector(400*8-1 downto 0);
  signal logits : std_logic_vector(10*32-1 downto 0);
begin
  -- conv1 --------------------------------------------------------------------
  u_swg1 : entity work.swg3x3 generic map (W => 28, H => 28, C => 1, DW => 8)
    port map (clk, rst, in_valid, in_ready, in_pixel, w1_v, w1_r, w1_d);
  u_mvau1 : entity work.mvau
    generic map (LAYER => 1, MW => 9, MH => 8, PE => PE1, SIMD => SIMD1,
                 RELU => true, SHIFT => SHIFT1, ODW => 8)
    port map (clk, rst, w1_v, w1_r, w1_d, c1_v, c1_r, c1_d);
  u_pool1 : entity work.maxpool2x2 generic map (W => 26, H => 26, C => 8, DW => 8)
    port map (clk, rst, c1_v, c1_r, c1_d, p1_v, p1_r, p1_d);

  -- decoupling FIFO (see results: without it Conv2 starves) --------------------
  g_fifo : if FIFO_DEPTH > 0 generate
    u_fifo1 : entity work.fifo generic map (DW => 64, DEPTH => FIFO_DEPTH)
      port map (clk, rst, p1_v, p1_r, p1_d, q1_v, q1_r, q1_d);
  end generate;
  g_nofifo : if FIFO_DEPTH = 0 generate          -- [ISE] was "else generate"
    q1_v <= p1_v; p1_r <= q1_r; q1_d <= p1_d;
  end generate;

  -- conv2 --------------------------------------------------------------------
  u_swg2 : entity work.swg3x3 generic map (W => 13, H => 13, C => 8, DW => 8)
    port map (clk, rst, q1_v, q1_r, q1_d, w2_v, w2_r, w2_d);
  u_mvau2 : entity work.mvau
    generic map (LAYER => 2, MW => 72, MH => 16, PE => PE2, SIMD => SIMD2,
                 RELU => true, SHIFT => SHIFT2, ODW => 8)
    port map (clk, rst, w2_v, w2_r, w2_d, c2_v, c2_r, c2_d);
  u_pool2 : entity work.maxpool2x2 generic map (W => 11, H => 11, C => 16, DW => 8)
    port map (clk, rst, c2_v, c2_r, c2_d, p2_v, p2_r, p2_d);

  -- flatten + dense + argmax -------------------------------------------------
  u_flat : entity work.collect generic map (N => 25, VW => 128)
    port map (clk, rst, p2_v, p2_r, p2_d, f_v, f_r, f_d);
  u_mvau3 : entity work.mvau
    generic map (LAYER => 3, MW => 400, MH => 10, PE => PE3, SIMD => SIMD3,
                 RELU => false, SHIFT => 0, ODW => 32)
    port map (clk, rst, f_v, f_r, f_d, out_valid, out_ready, logits);
  u_argmax : entity work.argmax generic map (N => 10, DW => 32)
    port map (logits, out_class);
end architecture;
