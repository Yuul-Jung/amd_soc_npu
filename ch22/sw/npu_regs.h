/* 22장 NPU 레지스터 맵 — 20장 npu_axi_lite.v 머리말 표와 같아야 한다. */
#ifndef NPU_REGS_H
#define NPU_REGS_H

#define NPU_CTRL      0x00u   /* W  bit0 START, bit1 CLR */
#define NPU_STATUS    0x04u   /* R  bit0 BUSY, bit1 DONE, bit2 ERROR */
#define NPU_CLASS     0x08u   /* R  [3:0] */
#define NPU_CYCLES    0x0Cu   /* R  [15:0] */
#define NPU_X_ADDR    0x10u   /* RW [9:0] */
#define NPU_X_DATA    0x14u   /* W  [7:0], X_ADDR +1 */
#define NPU_W_ADDR    0x18u   /* RW [19:16] 클래스, [9:0] 원소 */
#define NPU_W_DATA    0x1Cu   /* W  [7:0], 원소 +1 */
#define NPU_B_SEL     0x20u   /* RW [3:0] */
#define NPU_B_DATA    0x24u   /* W  [31:0], B_SEL +1 */
#define NPU_ID        0x28u   /* R  0x4E505531 */
#define NPU_LENGTH    0x2Cu   /* R  784 */
#define NPU_SCORE(k)  (0x40u + 4u * (unsigned)(k))   /* R  k = 0~9, signed 32비트 */

#define NPU_CTRL_START   (1u << 0)
#define NPU_CTRL_CLR     (1u << 1)
#define NPU_ST_BUSY      (1u << 0)
#define NPU_ST_DONE      (1u << 1)
#define NPU_ST_ERROR     (1u << 2)
#define NPU_ID_VALUE     0x4E505531u
#define NPU_N_IN         784
#define NPU_N_OUT        10

#endif
