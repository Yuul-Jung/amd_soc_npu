/* Vitis 기본 빌드(-O0)의 스택 1 KB(lscript.ld _STACK_SIZE 0x400)는 6-1~6-5 응용의 가장 깊은 호출
 * 경로(-fstack-usage 측정: 예) handle → sensor_frame 336 B → apply → xil_printf 약 350 B, 합계 약 960 B)에 비해 여유가 없다.
 * lscript.ld는 "_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x400" 이므로 여기서 절대 기호로 4 KB를 정의한다.
 * 보드 ELF에만 넣는다(PC 시뮬레이션 빌드에는 넣지 않는다). 확인: riscv32-xilinx-elf-size -A 의 .stack = 4096.
 */
__asm__(".global _STACK_SIZE\n.equ _STACK_SIZE, 0x1000\n");
