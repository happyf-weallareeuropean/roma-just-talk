#include "roma_windows_dpapi.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dpapi.h>

#pragma comment(lib, "Crypt32.lib")

static void roma_windows_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

static int roma_windows_validate(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
) {
    roma_windows_set_error(last_error, 0);
    if (input == NULL || input_count == 0 || output == NULL || output_count == NULL || input_count > UINT32_MAX) {
        return 0;
    }

    *output = NULL;
    *output_count = 0;
    return 1;
}

roma_windows_secret_status_t roma_windows_dpapi_protect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
) {
    if (!roma_windows_validate(input, input_count, output, output_count, last_error)) {
        return ROMA_WINDOWS_SECRET_INVALID_ARGUMENT;
    }

    DATA_BLOB data_in;
    DATA_BLOB data_out;
    data_in.pbData = (BYTE *)input;
    data_in.cbData = (DWORD)input_count;
    data_out.pbData = NULL;
    data_out.cbData = 0;

    if (!CryptProtectData(&data_in, L"roma-just-talk secret", NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &data_out)) {
        roma_windows_set_error(last_error, GetLastError());
        return ROMA_WINDOWS_SECRET_PROTECT_FAILED;
    }

    *output = (uint8_t *)data_out.pbData;
    *output_count = (size_t)data_out.cbData;
    return ROMA_WINDOWS_SECRET_OK;
}

roma_windows_secret_status_t roma_windows_dpapi_unprotect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
) {
    if (!roma_windows_validate(input, input_count, output, output_count, last_error)) {
        return ROMA_WINDOWS_SECRET_INVALID_ARGUMENT;
    }

    DATA_BLOB data_in;
    DATA_BLOB data_out;
    data_in.pbData = (BYTE *)input;
    data_in.cbData = (DWORD)input_count;
    data_out.pbData = NULL;
    data_out.cbData = 0;

    if (!CryptUnprotectData(&data_in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &data_out)) {
        roma_windows_set_error(last_error, GetLastError());
        return ROMA_WINDOWS_SECRET_UNPROTECT_FAILED;
    }

    *output = (uint8_t *)data_out.pbData;
    *output_count = (size_t)data_out.cbData;
    return ROMA_WINDOWS_SECRET_OK;
}

void roma_windows_secret_free(uint8_t *bytes) {
    if (bytes != NULL) {
        LocalFree((HLOCAL)bytes);
    }
}

#else

static void roma_windows_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

roma_windows_secret_status_t roma_windows_dpapi_protect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
) {
    (void)input;
    (void)input_count;
    if (output != NULL) {
        *output = NULL;
    }
    if (output_count != NULL) {
        *output_count = 0;
    }
    roma_windows_set_error(last_error, 0);
    return ROMA_WINDOWS_SECRET_UNSUPPORTED;
}

roma_windows_secret_status_t roma_windows_dpapi_unprotect(
    const uint8_t *input,
    size_t input_count,
    uint8_t **output,
    size_t *output_count,
    uint32_t *last_error
) {
    (void)input;
    (void)input_count;
    if (output != NULL) {
        *output = NULL;
    }
    if (output_count != NULL) {
        *output_count = 0;
    }
    roma_windows_set_error(last_error, 0);
    return ROMA_WINDOWS_SECRET_UNSUPPORTED;
}

void roma_windows_secret_free(uint8_t *bytes) {
    (void)bytes;
}

#endif
