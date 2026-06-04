#ifndef ROMA_WINDOWS_DPAPI_H
#define ROMA_WINDOWS_DPAPI_H

#include <stddef.h>
#include <stdint.h>

#include "roma_windows_keyboard_hook.h"
#include "roma_windows_foreground.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum roma_windows_secret_status {
    ROMA_WINDOWS_SECRET_OK = 0,
    ROMA_WINDOWS_SECRET_UNSUPPORTED = 1,
    ROMA_WINDOWS_SECRET_INVALID_ARGUMENT = 2,
    ROMA_WINDOWS_SECRET_PROTECT_FAILED = 3,
    ROMA_WINDOWS_SECRET_UNPROTECT_FAILED = 4
} roma_windows_secret_status_t;

roma_windows_secret_status_t roma_windows_dpapi_protect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
);

roma_windows_secret_status_t roma_windows_dpapi_unprotect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
);

void roma_windows_secret_free(uint8_t *bytes);

#ifdef __cplusplus
}
#endif

#endif
