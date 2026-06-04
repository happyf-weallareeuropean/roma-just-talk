#ifndef ROMA_WINDOWS_FOREGROUND_H
#define ROMA_WINDOWS_FOREGROUND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum roma_windows_foreground_status {
    ROMA_WINDOWS_FOREGROUND_OK = 0,
    ROMA_WINDOWS_FOREGROUND_UNSUPPORTED = 1,
    ROMA_WINDOWS_FOREGROUND_INVALID_ARGUMENT = 2,
    ROMA_WINDOWS_FOREGROUND_WINDOW_NOT_FOUND = 3,
    ROMA_WINDOWS_FOREGROUND_ACTIVATION_FAILED = 4
} roma_windows_foreground_status_t;

roma_windows_foreground_status_t roma_windows_foreground_activate_process(
    uint32_t process_id,
    uint32_t *last_error
);

#ifdef __cplusplus
}
#endif

#endif
