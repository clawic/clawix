#include "ClawixSimulatorKitShim.h"

__attribute__((naked))
void ClawixSimKitConnectDisplayView(void *function, void *displayView, void *screen, uintptr_t inputs) {
#if defined(__aarch64__)
    __asm__ volatile(
        "sub sp, sp, #48\n"
        "stp x20, x21, [sp, #16]\n"
        "str x30, [sp, #32]\n"
        "str x3, [sp]\n"
        "mov x16, x0\n"
        "mov x20, x1\n"
        "mov x21, #0\n"
        "mov x0, x2\n"
        "mov x1, sp\n"
        "blr x16\n"
        "ldr x30, [sp, #32]\n"
        "ldp x20, x21, [sp, #16]\n"
        "add sp, sp, #48\n"
        "ret\n"
    );
#else
    (void)function; (void)displayView; (void)screen; (void)inputs;
    __builtin_trap();
#endif
}
