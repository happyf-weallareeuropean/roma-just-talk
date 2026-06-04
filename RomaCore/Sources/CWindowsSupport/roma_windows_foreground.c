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

static BOOL roma_windows_foreground_attach_input(
    DWORD current_thread_id,
    DWORD other_thread_id,
    BOOL *attached
) {
    *attached = FALSE;
    if (other_thread_id == 0 || other_thread_id == current_thread_id) {
        return TRUE;
    }

    *attached = AttachThreadInput(current_thread_id, other_thread_id, TRUE);
    return *attached;
}

static void roma_windows_foreground_detach_input(
    DWORD current_thread_id,
    DWORD other_thread_id,
    BOOL attached
) {
    if (attached) {
        AttachThreadInput(current_thread_id, other_thread_id, FALSE);
    }
}

static BOOL roma_windows_foreground_try_activate(HWND window) {
    DWORD current_thread_id = GetCurrentThreadId();
    DWORD target_thread_id = GetWindowThreadProcessId(window, NULL);
    HWND foreground_window = GetForegroundWindow();
    DWORD foreground_thread_id = foreground_window != NULL
        ? GetWindowThreadProcessId(foreground_window, NULL)
        : 0;
    BOOL target_attached = FALSE;
    BOOL foreground_attached = FALSE;
    BOOL activated = FALSE;

    ShowWindow(window, SW_RESTORE);
    roma_windows_foreground_attach_input(current_thread_id, foreground_thread_id, &foreground_attached);
    if (target_thread_id != foreground_thread_id) {
        roma_windows_foreground_attach_input(current_thread_id, target_thread_id, &target_attached);
    }
    BringWindowToTop(window);
    SetActiveWindow(window);
    activated = SetForegroundWindow(window);
    roma_windows_foreground_detach_input(current_thread_id, target_thread_id, target_attached);
    roma_windows_foreground_detach_input(current_thread_id, foreground_thread_id, foreground_attached);

    return activated;
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

    if (!roma_windows_foreground_try_activate(state.window)) {
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
