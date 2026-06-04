#include "roma_windows_foreground.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#pragma comment(lib, "User32.lib")

typedef struct roma_windows_foreground_state {
    DWORD process_id;
    HWND window;
} roma_windows_foreground_state_t;

static void roma_windows_foreground_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

static BOOL CALLBACK roma_windows_foreground_enum_proc(HWND window, LPARAM param) {
    roma_windows_foreground_state_t *state = (roma_windows_foreground_state_t *)param;
    DWORD window_process_id = 0;

    if (!IsWindowVisible(window)) {
        return TRUE;
    }

    GetWindowThreadProcessId(window, &window_process_id);
    if (window_process_id != state->process_id) {
        return TRUE;
    }

    state->window = window;
    return FALSE;
}

roma_windows_foreground_status_t roma_windows_foreground_activate_process(
    uint32_t process_id,
    uint32_t *last_error
) {
    roma_windows_foreground_set_error(last_error, 0);
    if (process_id == 0) {
        return ROMA_WINDOWS_FOREGROUND_INVALID_ARGUMENT;
    }

    roma_windows_foreground_state_t state;
    state.process_id = (DWORD)process_id;
    state.window = NULL;
    EnumWindows(roma_windows_foreground_enum_proc, (LPARAM)&state);
    if (state.window == NULL) {
        return ROMA_WINDOWS_FOREGROUND_WINDOW_NOT_FOUND;
    }

    ShowWindow(state.window, SW_RESTORE);
    if (!SetForegroundWindow(state.window)) {
        roma_windows_foreground_set_error(last_error, GetLastError());
        return ROMA_WINDOWS_FOREGROUND_ACTIVATION_FAILED;
    }

    return ROMA_WINDOWS_FOREGROUND_OK;
}

#else

static void roma_windows_foreground_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

roma_windows_foreground_status_t roma_windows_foreground_activate_process(
    uint32_t process_id,
    uint32_t *last_error
) {
    (void)process_id;
    roma_windows_foreground_set_error(last_error, 0);
    return ROMA_WINDOWS_FOREGROUND_UNSUPPORTED;
}

#endif
