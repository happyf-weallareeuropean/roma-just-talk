#ifndef ROMA_WINDOWS_KEYBOARD_HOOK_H
#define ROMA_WINDOWS_KEYBOARD_HOOK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum roma_windows_keyboard_status {
    ROMA_WINDOWS_KEYBOARD_OK = 0,
    ROMA_WINDOWS_KEYBOARD_UNSUPPORTED = 1,
    ROMA_WINDOWS_KEYBOARD_INSTALL_FAILED = 2,
    ROMA_WINDOWS_KEYBOARD_MESSAGE_LOOP_FAILED = 3,
    ROMA_WINDOWS_KEYBOARD_TIMEOUT = 4
} roma_windows_keyboard_status_t;

enum {
    ROMA_WINDOWS_KEYBOARD_MOD_CONTROL = 1u << 0,
    ROMA_WINDOWS_KEYBOARD_MOD_SHIFT = 1u << 1,
    ROMA_WINDOWS_KEYBOARD_MOD_ALT = 1u << 2,
    ROMA_WINDOWS_KEYBOARD_MOD_WIN = 1u << 3
};

enum {
    ROMA_WINDOWS_KEYBOARD_EVENT_KEY_DOWN = 1u << 0,
    ROMA_WINDOWS_KEYBOARD_EVENT_KEY_UP = 1u << 1
};

roma_windows_keyboard_status_t roma_windows_keyboard_wait_for_hold(
    uint32_t virtual_key,
    uint32_t required_modifiers,
    uint32_t timeout_milliseconds,
    uint32_t *observed_events,
    uint32_t *last_error
);

#ifdef __cplusplus
}
#endif

#endif
