#include "roma_windows_keyboard_hook.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#pragma comment(lib, "User32.lib")

#define ROMA_KEYBOARD_DONE_MESSAGE (WM_APP + 0x523)

typedef struct roma_keyboard_state {
    uint32_t virtual_key;
    uint32_t required_modifiers;
    uint32_t observed_events;
    uint32_t modifier_state;
    int target_is_down;
    DWORD thread_id;
    HHOOK hook;
} roma_keyboard_state_t;

static roma_keyboard_state_t g_keyboard_state;

static void roma_windows_keyboard_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

static int roma_windows_keyboard_is_key_down_message(WPARAM message) {
    return message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
}

static int roma_windows_keyboard_is_key_up_message(WPARAM message) {
    return message == WM_KEYUP || message == WM_SYSKEYUP;
}

static uint32_t roma_windows_keyboard_modifier_for_vk(DWORD virtual_key) {
    switch (virtual_key) {
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
        return ROMA_WINDOWS_KEYBOARD_MOD_CONTROL;
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
        return ROMA_WINDOWS_KEYBOARD_MOD_SHIFT;
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
        return ROMA_WINDOWS_KEYBOARD_MOD_ALT;
    case VK_LWIN:
    case VK_RWIN:
        return ROMA_WINDOWS_KEYBOARD_MOD_WIN;
    default:
        return 0;
    }
}

static void roma_windows_keyboard_update_modifier(DWORD virtual_key, WPARAM message) {
    uint32_t modifier = roma_windows_keyboard_modifier_for_vk(virtual_key);
    if (modifier == 0) {
        return;
    }

    if (roma_windows_keyboard_is_key_down_message(message)) {
        g_keyboard_state.modifier_state |= modifier;
    } else if (roma_windows_keyboard_is_key_up_message(message)) {
        g_keyboard_state.modifier_state &= ~modifier;
    }
}

static LRESULT CALLBACK roma_windows_keyboard_proc(int code, WPARAM w_param, LPARAM l_param) {
    if (code == HC_ACTION && l_param != 0) {
        KBDLLHOOKSTRUCT *event = (KBDLLHOOKSTRUCT *)l_param;
        DWORD virtual_key = event->vkCode;

        roma_windows_keyboard_update_modifier(virtual_key, w_param);

        if (virtual_key == g_keyboard_state.virtual_key) {
            int required_modifiers_down = (g_keyboard_state.modifier_state & g_keyboard_state.required_modifiers)
                == g_keyboard_state.required_modifiers;

            if (roma_windows_keyboard_is_key_down_message(w_param) && required_modifiers_down) {
                g_keyboard_state.target_is_down = 1;
                g_keyboard_state.observed_events |= ROMA_WINDOWS_KEYBOARD_EVENT_KEY_DOWN;
            } else if (roma_windows_keyboard_is_key_up_message(w_param) && g_keyboard_state.target_is_down) {
                g_keyboard_state.target_is_down = 0;
                g_keyboard_state.observed_events |= ROMA_WINDOWS_KEYBOARD_EVENT_KEY_UP;
                PostThreadMessageA(g_keyboard_state.thread_id, ROMA_KEYBOARD_DONE_MESSAGE, 0, 0);
            }
        }
    }

    return CallNextHookEx(g_keyboard_state.hook, code, w_param, l_param);
}

roma_windows_keyboard_status_t roma_windows_keyboard_wait_for_hold(
    uint32_t virtual_key,
    uint32_t required_modifiers,
    uint32_t timeout_milliseconds,
    uint32_t *observed_events,
    uint32_t *last_error
) {
    if (observed_events != NULL) {
        *observed_events = 0;
    }
    roma_windows_keyboard_set_error(last_error, 0);

    g_keyboard_state.virtual_key = virtual_key;
    g_keyboard_state.required_modifiers = required_modifiers;
    g_keyboard_state.observed_events = 0;
    g_keyboard_state.modifier_state = 0;
    g_keyboard_state.target_is_down = 0;
    g_keyboard_state.thread_id = GetCurrentThreadId();
    g_keyboard_state.hook = SetWindowsHookExA(WH_KEYBOARD_LL, roma_windows_keyboard_proc, GetModuleHandleA(NULL), 0);
    if (g_keyboard_state.hook == NULL) {
        roma_windows_keyboard_set_error(last_error, GetLastError());
        return ROMA_WINDOWS_KEYBOARD_INSTALL_FAILED;
    }

    UINT_PTR timer_id = 0;
    if (timeout_milliseconds > 0) {
        timer_id = SetTimer(NULL, 0, timeout_milliseconds, NULL);
        if (timer_id == 0) {
            roma_windows_keyboard_set_error(last_error, GetLastError());
            UnhookWindowsHookEx(g_keyboard_state.hook);
            g_keyboard_state.hook = NULL;
            return ROMA_WINDOWS_KEYBOARD_INSTALL_FAILED;
        }
    }

    roma_windows_keyboard_status_t status = ROMA_WINDOWS_KEYBOARD_MESSAGE_LOOP_FAILED;
    MSG message;
    while (GetMessageA(&message, NULL, 0, 0) > 0) {
        if (message.message == ROMA_KEYBOARD_DONE_MESSAGE) {
            status = ROMA_WINDOWS_KEYBOARD_OK;
            break;
        }

        if (timer_id != 0 && message.message == WM_TIMER && message.wParam == timer_id) {
            status = ROMA_WINDOWS_KEYBOARD_TIMEOUT;
            break;
        }

        TranslateMessage(&message);
        DispatchMessageA(&message);
    }

    if (timer_id != 0) {
        KillTimer(NULL, timer_id);
    }

    UnhookWindowsHookEx(g_keyboard_state.hook);
    g_keyboard_state.hook = NULL;

    if (observed_events != NULL) {
        *observed_events = g_keyboard_state.observed_events;
    }
    return status;
}

#else

static void roma_windows_keyboard_set_error(uint32_t *last_error, uint32_t value) {
    if (last_error != NULL) {
        *last_error = value;
    }
}

roma_windows_keyboard_status_t roma_windows_keyboard_wait_for_hold(
    uint32_t virtual_key,
    uint32_t required_modifiers,
    uint32_t timeout_milliseconds,
    uint32_t *observed_events,
    uint32_t *last_error
) {
    (void)virtual_key;
    (void)required_modifiers;
    (void)timeout_milliseconds;
    if (observed_events != NULL) {
        *observed_events = 0;
    }
    roma_windows_keyboard_set_error(last_error, 0);
    return ROMA_WINDOWS_KEYBOARD_UNSUPPORTED;
}

#endif
