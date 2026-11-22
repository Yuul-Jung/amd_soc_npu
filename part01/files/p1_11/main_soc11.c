#include "xparameters.h"
#include "xgpio.h"
#include "xuartlite_l.h"
#include "xtmrctr.h"
#include "xstatus.h"
#include "xil_types.h"
#include "xil_exception.h"

#ifdef SDT
#include "xinterrupt_wrap.h"
#else
#include "xintc.h"
#endif

/*
 * SoC 11 - 사용자 Top 기반 MicroBlaze V + GPIO/UART/Timer/INTC 실습
 *
 * GPIO Channel 1 : LED[15:0] output
 * GPIO Channel 2 : SW[15:0] input
 *
 * LED ownership:
 *   LED0      : SW0 mirror (SW_LED_MASK의 bit0만 사용)
 *   LED[13:1] : 현재 C 출력에서는 0 (하드웨어 핀은 분리하지 않음)
 *   LED14     : UART command control ('1' = ON, '0' = OFF)
 *   LED15     : Timer interrupt heartbeat
 *
 * UART : Polling, 115200 8N1
 * Timer: 100 MHz, 0.5 s interval, Down Count + Auto Reload + Interrupt
 * IRQ  : AXI Timer -> AXI INTC -> MicroBlaze V
 */

// (참고) AXI GPIO Channel 1: LED 출력, Channel 2: 스위치 입력
#define GPIO_LED_CHANNEL        1U
#define GPIO_SW_CHANNEL         2U

// (변경) 11장 독립 실습: 스위치 한 비트(SW0)만 LED0에 반영
#define SW_LED_MASK             0x00000001U
// (유지) bit14=UART 표시, bit15=Timer 표시. SW_LED_MASK와 비트 중복 금지
#define UART_LED_MASK           0x00004000U
#define HEARTBEAT_LED_MASK      0x00008000U

#define TIMER0                  0U
// (유지) 100 MHz 기준 0.5초에 해당하는 50,000,000 tick
#define TIMER_TICKS_500MS       50000000U
#define TIMER_RESET_VALUE       (TIMER_TICKS_500MS - 2U)

// (참고) 사용 중인 Vitis BSP의 SDT 여부에 따라 장치 식별자/기준 주소 선택
#ifndef SDT
#define GPIO_DEVICE_ID          XPAR_GPIO_0_DEVICE_ID
#define TIMER_DEVICE_ID         XPAR_TMRCTR_0_DEVICE_ID
#define INTC_DEVICE_ID          XPAR_INTC_0_DEVICE_ID
#define TIMER_INTERRUPT_ID      XPAR_INTC_0_TMRCTR_0_VEC_ID
#define UART_BASEADDR           XPAR_UARTLITE_0_BASEADDR
#else
#define GPIO_BASEADDR           XPAR_XGPIO_0_BASEADDR
#define TIMER_BASEADDR          XPAR_XTMRCTR_0_BASEADDR
#define UART_BASEADDR           XPAR_XUARTLITE_0_BASEADDR
#endif

static XGpio Gpio;
static XTmrCtr Timer;

#ifndef SDT
static XIntc Intc;
#endif

// (유지) 인터럽트에서 변경되는 공유 카운터
volatile u32 interrupt_count = 0U;
volatile u32 switch_value    = 0U;
volatile u32 led_state       = 0U;
volatile u8  last_uart_rx    = 0U;

static u32 uart_led_state = 0U;

// (유지) UART Lite 바이트 전송용 최소 출력 함수
static void UartPutChar(u8 ch)
{
    XUartLite_SendByte(UART_BASEADDR, ch);
}

static void UartPutString(const char *text)
{
    while (*text != '\0') {
        UartPutChar((u8)*text);
        text++;
    }
}

static void UartPutHexNibble(u8 value)
{
    value &= 0x0FU;

    if (value < 10U) {
        UartPutChar((u8)('0' + value));
    } else {
        UartPutChar((u8)('A' + (value - 10U)));
    }
}

static void UartPutHex16(u16 value)
{
    int shift;

    for (shift = 12; shift >= 0; shift -= 4) {
        UartPutHexNibble((u8)(value >> shift));
    }
}

static void UartPutHex32(u32 value)
{
    int shift;

    for (shift = 28; shift >= 0; shift -= 4) {
        UartPutHexNibble((u8)(value >> shift));
    }
}

static void PrintHelp(void)
{
    UartPutString("\r\nCommands\r\n");
    UartPutString("  1 : LED14 ON\r\n");
    UartPutString("  0 : LED14 OFF\r\n");
    UartPutString("  r : Read status\r\n");
    UartPutString("  h : Help\r\n");
}

// (유지) 터미널의 'r' 명령에 현재 SW/LED/IRQ 상태를 출력
static void PrintStatus(void)
{
    UartPutString("\r\nSW=0x");
    UartPutHex16((u16)switch_value);
    UartPutString(" LED=0x");
    UartPutHex16((u16)led_state);
    UartPutString(" IRQ=0x");
    UartPutHex32(interrupt_count);
    UartPutString("\r\n");
}

// (유지) Timer 인터럽트 콜백은 카운트만 증가시켜 실행 시간을 최소화
static void TimerCallback(void *CallBackRef, u8 TmrCtrNumber)
{
    (void)CallBackRef;
    (void)TmrCtrNumber;
    interrupt_count++;
}

// (유지) AXI GPIO 드라이버 초기화; 채널 방향은 기존 BD 설정을 사용
static int InitGpio(void)
{
#ifndef SDT
    return XGpio_Initialize(&Gpio, GPIO_DEVICE_ID);
#else
    return XGpio_Initialize(&Gpio, GPIO_BASEADDR);
#endif
}

// (유지) Timer SelfTest → 콜백 등록 → Down Count/Auto Reload/IRQ 설정
static int InitTimer(void)
{
    int status;

#ifndef SDT
    status = XTmrCtr_Initialize(&Timer, TIMER_DEVICE_ID);
#else
    status = XTmrCtr_Initialize(&Timer, TIMER_BASEADDR);
#endif

    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    status = XTmrCtr_SelfTest(&Timer, TIMER0);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    XTmrCtr_SetHandler(&Timer, TimerCallback, &Timer);
    XTmrCtr_SetOptions(
        &Timer,
        TIMER0,
        XTC_DOWN_COUNT_OPTION |
        XTC_AUTO_RELOAD_OPTION |
        XTC_INT_MODE_OPTION
    );
    XTmrCtr_SetResetValue(&Timer, TIMER0, TIMER_RESET_VALUE);

    return XST_SUCCESS;
}

// (유지) AXI INTC/CPU 인터럽트를 Timer 인터럽트 핸들러와 연결
static int SetupInterruptSystem(void)
{
    int status;

#ifndef SDT
    status = XIntc_Initialize(&Intc, INTC_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    status = XIntc_Connect(
        &Intc,
        TIMER_INTERRUPT_ID,
        (XInterruptHandler)XTmrCtr_InterruptHandler,
        (void *)&Timer
    );
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    status = XIntc_Start(&Intc, XIN_REAL_MODE);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    XIntc_Enable(&Intc, TIMER_INTERRUPT_ID);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XIntc_InterruptHandler,
        &Intc
    );
    Xil_ExceptionEnable();
#else
    status = XSetupInterruptSystem(
        &Timer,
        (XInterruptHandler)XTmrCtr_InterruptHandler,
        Timer.Config.IntrId,
        Timer.Config.IntrParent,
        XINTERRUPT_DEFAULT_PRIORITY
    );

    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }
#endif

    return XST_SUCCESS;
}

// (유지) UART RX/TX FIFO를 초기화하며 UART 자체 IRQ는 사용하지 않음
static void InitUart(void)
{
    /* RX/TX FIFO clear. UART interrupt remains disabled. */
    XUartLite_WriteReg(
        UART_BASEADDR,
        XUL_CONTROL_REG_OFFSET,
        0x03U
    );
}

// (유지) 폴링 방식으로 문자 '1'/'0'을 LED14 상태에 반영
static void HandleUartCommand(void)
{
    // 수신 데이터가 없으면 곧바로 반환해 SW 읽기·Timer 동작을 막지 않음
    if (XUartLite_IsReceiveEmpty(UART_BASEADDR)) {
        return;
    }

    last_uart_rx = XUartLite_RecvByte(UART_BASEADDR);

    switch (last_uart_rx) {
    case '1':
        uart_led_state = UART_LED_MASK;
        UartPutString("\r\nLED14=ON\r\n");
        break;

    case '0':
        uart_led_state = 0U;
        UartPutString("\r\nLED14=OFF\r\n");
        break;

    case 'r':
    case 'R':
        PrintStatus();
        break;

    case 'h':
    case 'H':
        PrintHelp();
        break;

    case '\r':
    case '\n':
        break;

    default:
        UartPutString("\r\nUnknown command. Press h.\r\n");
        break;
    }
}

// (핵심) SW0, UART 명령, Timer heartbeat의 비트를 합쳐 LED 출력 계산
static void UpdateLedOutput(void)
{
    u32 new_led_state;
    u32 heartbeat_state;

    if ((interrupt_count & 1U) != 0U) {
        heartbeat_state = HEARTBEAT_LED_MASK;
    } else {
        heartbeat_state = 0U;
    }

    // SW0(bit0) + UART(bit14) + Timer(bit15)를 비트 OR로 합침
    // sw[15:1] 입력은 유지하지만 현재 LED1~13에는 출력하지 않음
    new_led_state =
        (switch_value & SW_LED_MASK) |
        uart_led_state |
        heartbeat_state;

    // LED 값이 실제로 바뀌었을 때만 AXI GPIO 출력 레지스터에 기록
    if (new_led_state != led_state) {
        led_state = new_led_state;
        XGpio_DiscreteWrite(
            &Gpio,
            GPIO_LED_CHANNEL,
            led_state
        );
    }
}

// (핵심) GPIO/UART/Timer/Interrupt를 준비한 뒤 입력→출력을 반복
int main(void)
{
    int status;

    status = InitGpio();
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    InitUart();

    status = InitTimer();
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    status = SetupInterruptSystem();
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    led_state = 0U;
    XGpio_DiscreteWrite(&Gpio, GPIO_LED_CHANNEL, led_state);

    UartPutString("\r\nSoC 10 Integrated System Ready\r\n");
    PrintHelp();

    XTmrCtr_Start(&Timer, TIMER0);

    // SW 값을 읽고 → UART 명령 처리 → 최종 LED 값을 출력하는 메인 루프
    while (1) {
        switch_value = XGpio_DiscreteRead(
            &Gpio,
            GPIO_SW_CHANNEL
        );

        HandleUartCommand();
        UpdateLedOutput();
    }

    return XST_SUCCESS;
}
