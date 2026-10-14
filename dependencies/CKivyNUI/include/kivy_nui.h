/*
 * kivy_nui.h — the shared C api between the Swift host and Kivy.
 *
 * One shared library, linked by both sides of the same process:
 *
 *   - the Swift host (KivyRepresentable), which owns the GPU and the
 *     display sync, implements the GL table on NucleantVulkan, and draws
 *     Kivy's output with its own shader node;
 *   - Kivy's Cython side (`cgl_nui.pyx`, `_window_nui.pyx`), which renders
 *     through it and reads its input from it as it did from SDL.
 *
 * Each side registers a table of callbacks with the library; the exported
 * `kivy_nui_*` functions forward to the other side's table. Whichever side
 * calls, it only ever talks to this library, never to the other side
 * directly.
 *
 * Order of events:
 *   1. The host registers itself (`kivy_nui_set_host`), then starts Python.
 *   2. Kivy picks the `nui` window / cgl backend (`kivy_nui_is_hosted`),
 *      copies the host's GLES2 table (`kivy_nui_gl`, kivy_nui_gl.h) into its
 *      own, and registers its tick (`kivy_nui_set_kivy`).
 *   3. Every display-sync frame the host calls `kivy_nui_tick`; Kivy drains
 *      `kivy_nui_poll_event`, runs its clock and draws, then calls
 *      `kivy_nui_present`.
 *
 * Everything here is called on the main thread.
 *
 * Coordinates: events carry *window-system* coordinates, top-left origin,
 * y down — exactly what SDL handed Kivy. Kivy's own code turns them into its
 * bottom-left space (`window_sdl2.py` `_fix_mouse_pos`, the mouse provider's
 * `1.0 - ny`, the touch provider's `1 - y`), so they must not be flipped
 * before they get here.
 *
 * Key codes, scan codes, modifier bits and mouse button numbers use SDL2's
 * values, so the window provider keeps Kivy's existing key mapping.
 */

#ifndef KIVY_NUI_H
#define KIVY_NUI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "kivy_nui_gl.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KIVY_NUI_API __attribute__((visibility("default")))

#define KIVY_NUI_API_VERSION 1

/* MARK: - Window metrics */

typedef struct KivyNUIWindowMetrics {
    /* Window size in window-system units (points), as SDL_GetWindowSize. */
    int32_t width;
    int32_t height;
    /* Size of the shared render target in pixels, as SDL_GL_GetDrawableSize.
       This is what framebuffer 0 is in the GL table. */
    int32_t pixel_width;
    int32_t pixel_height;
    /* pixel_width / width. */
    float density;
    float dpi;
} KivyNUIWindowMetrics;

/* MARK: - Events (host -> Kivy) */

/* One per action `_window_sdl2.pyx` `poll()` returns, minus joysticks. */
typedef enum KivyNUIEventType {
    KIVY_NUI_EVENT_NONE = 0,
    KIVY_NUI_EVENT_QUIT,

    KIVY_NUI_EVENT_MOUSE_MOTION,
    KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN,
    KIVY_NUI_EVENT_MOUSE_BUTTON_UP,
    KIVY_NUI_EVENT_MOUSE_WHEEL,

    KIVY_NUI_EVENT_FINGER_MOTION,
    KIVY_NUI_EVENT_FINGER_DOWN,
    KIVY_NUI_EVENT_FINGER_UP,

    KIVY_NUI_EVENT_KEY_DOWN,
    KIVY_NUI_EVENT_KEY_UP,
    KIVY_NUI_EVENT_TEXT_INPUT,
    KIVY_NUI_EVENT_TEXT_EDIT,

    KIVY_NUI_EVENT_WINDOW_EXPOSED,
    KIVY_NUI_EVENT_WINDOW_RESIZED,
    KIVY_NUI_EVENT_WINDOW_MINIMIZED,
    KIVY_NUI_EVENT_WINDOW_MAXIMIZED,
    KIVY_NUI_EVENT_WINDOW_RESTORED,
    KIVY_NUI_EVENT_WINDOW_SHOWN,
    KIVY_NUI_EVENT_WINDOW_HIDDEN,
    KIVY_NUI_EVENT_WINDOW_ENTER,
    KIVY_NUI_EVENT_WINDOW_LEAVE,
    KIVY_NUI_EVENT_WINDOW_FOCUS_GAINED,
    KIVY_NUI_EVENT_WINDOW_FOCUS_LOST,
    KIVY_NUI_EVENT_WINDOW_CLOSE,
    KIVY_NUI_EVENT_WINDOW_MOVED,
    KIVY_NUI_EVENT_WINDOW_DISPLAY_CHANGED,

    KIVY_NUI_EVENT_DROP_BEGIN,
    KIVY_NUI_EVENT_DROP_FILE,
    KIVY_NUI_EVENT_DROP_TEXT,
    KIVY_NUI_EVENT_DROP_END,

    KIVY_NUI_EVENT_APP_TERMINATING,
    KIVY_NUI_EVENT_APP_LOW_MEMORY,
    KIVY_NUI_EVENT_APP_WILL_ENTER_BACKGROUND,
    KIVY_NUI_EVENT_APP_DID_ENTER_BACKGROUND,
    KIVY_NUI_EVENT_APP_WILL_ENTER_FOREGROUND,
    KIVY_NUI_EVENT_APP_DID_ENTER_FOREGROUND,
} KivyNUIEventType;

/* SDL's text event size, so TEXT_INPUT / TEXT_EDIT carry the same chunks. */
#define KIVY_NUI_TEXT_SIZE 32

/* MOUSE_MOTION, MOUSE_BUTTON_*: window coordinates, top-left.
   button: 1 left, 2 middle, 3 right, 4, 5 (SDL numbering). */
typedef struct KivyNUIMouseEvent { int32_t x, y; uint8_t button; } KivyNUIMouseEvent;
/* MOUSE_WHEEL: deltas with SDL_MouseWheelEvent's sign convention, plus the
   cursor's window position (top-left) — what SDL's window asked
   SDL_GetMouseState for. */
typedef struct KivyNUIWheelEvent { int32_t x, y; int32_t mouse_x, mouse_y; } KivyNUIWheelEvent;
/* FINGER_*: normalized 0...1 over the window, top-left. */
typedef struct KivyNUIFingerEvent { int64_t finger_id; float x, y, pressure; } KivyNUIFingerEvent;
/* KEY_*: SDL2 keycode / scancode / KMOD_* bits. */
typedef struct KivyNUIKeyEvent { int32_t keycode; int32_t scancode; uint16_t mod; } KivyNUIKeyEvent;
/* TEXT_INPUT, TEXT_EDIT: NUL-terminated UTF-8. */
typedef struct KivyNUITextEvent { char utf8[KIVY_NUI_TEXT_SIZE]; } KivyNUITextEvent;
/* WINDOW_RESIZED (w, h), WINDOW_MOVED (x, y),
   WINDOW_DISPLAY_CHANGED (display index, unused). */
typedef struct KivyNUIWindowEvent { int32_t data1, data2; } KivyNUIWindowEvent;
/* DROP_FILE, DROP_TEXT: NUL-terminated UTF-8, owned by the library, valid
   until the next `kivy_nui_poll_event`. DROP_BEGIN: the cursor's window
   position (top-left) in x, y. */
typedef struct KivyNUIDropEvent { const char *utf8; int32_t x, y; } KivyNUIDropEvent;

typedef struct KivyNUIEvent {
    KivyNUIEventType type;
    union {
        KivyNUIMouseEvent  mouse;
        KivyNUIWheelEvent  wheel;
        KivyNUIFingerEvent finger;
        KivyNUIKeyEvent    key;
        KivyNUITextEvent   text;
        KivyNUIWindowEvent window;
        KivyNUIDropEvent   drop;
    };
} KivyNUIEvent;

/* MARK: - System cursors */

/* The names `window_sdl2.py` `set_system_cursor` accepts. */
typedef enum KivyNUICursor {
    KIVY_NUI_CURSOR_ARROW = 0,
    KIVY_NUI_CURSOR_IBEAM,
    KIVY_NUI_CURSOR_WAIT,
    KIVY_NUI_CURSOR_CROSSHAIR,
    KIVY_NUI_CURSOR_WAIT_ARROW,
    KIVY_NUI_CURSOR_SIZE_NWSE,
    KIVY_NUI_CURSOR_SIZE_NESW,
    KIVY_NUI_CURSOR_SIZE_WE,
    KIVY_NUI_CURSOR_SIZE_NS,
    KIVY_NUI_CURSOR_SIZE_ALL,
    KIVY_NUI_CURSOR_NO,
    KIVY_NUI_CURSOR_HAND,
} KivyNUICursor;

/* MARK: - Host side (registered by KivyRepresentable) */

typedef struct KivyNUIHost {
    /* Passed back as the first argument of every callback. */
    void *context;

    /* GPU. The host's GLES2 implementation, rendering into the shared image
       the shader node draws (framebuffer 0); see kivy_nui_gl.h. Must stay
       valid while the host is registered. */
    const KivyNUIGL *gl;
    /* Kivy finished a frame into framebuffer 0 (Window.flip). */
    void (*present)(void *context);

    /* Window. */
    void (*get_window_metrics)(void *context, KivyNUIWindowMetrics *out);
    void (*set_title)(void *context, const char *utf8);
    void (*set_system_cursor)(void *context, KivyNUICursor cursor);
    void (*set_cursor_visible)(void *context, bool visible);
    void (*show_keyboard)(void *context);
    void (*hide_keyboard)(void *context);
    /* Kivy asked to close (App.stop / Window.close). */
    void (*request_close)(void *context);
} KivyNUIHost;

/* Registers the host. Called once, before Python is started. The table is
   copied; NULL unregisters. */
KIVY_NUI_API void kivy_nui_set_host(const KivyNUIHost *host);

/* True once a host is registered: Kivy's `nui` window and cgl backend are
   only usable inside the Swift host. */
KIVY_NUI_API bool kivy_nui_is_hosted(void);

/* MARK: - Kivy side (registered by `_window_nui.pyx`) */

typedef struct KivyNUIKivy {
    /* Passed back as the first argument of every callback. */
    void *context;

    /* One display-sync frame. `dt` is seconds since the previous tick.
       Kivy drains `kivy_nui_poll_event`, ticks its clock, draws and calls
       `kivy_nui_present` — what one pass of its own main loop did. */
    void (*tick)(void *context, double dt);
} KivyNUIKivy;

/* Registers Kivy. The table is copied; NULL unregisters. */
KIVY_NUI_API void kivy_nui_set_kivy(const KivyNUIKivy *kivy);

/* MARK: - Called by Kivy (forwarded to the host) */

/* The host's GLES2 table, for `cgl_nui.pyx` to copy into Kivy's
   `GLES2_Context`. NULL when no host is registered. */
KIVY_NUI_API const KivyNUIGL *kivy_nui_gl(void);
KIVY_NUI_API void kivy_nui_present(void);

KIVY_NUI_API void kivy_nui_get_window_metrics(KivyNUIWindowMetrics *out);
KIVY_NUI_API void kivy_nui_set_title(const char *utf8);
KIVY_NUI_API void kivy_nui_set_system_cursor(KivyNUICursor cursor);
KIVY_NUI_API void kivy_nui_set_cursor_visible(bool visible);
KIVY_NUI_API void kivy_nui_show_keyboard(void);
KIVY_NUI_API void kivy_nui_hide_keyboard(void);
KIVY_NUI_API void kivy_nui_request_close(void);

/* Takes the oldest queued event into `out`. False when the queue is empty,
   the way SDL_PollEvent returns 0. */
KIVY_NUI_API bool kivy_nui_poll_event(KivyNUIEvent *out);

/* MARK: - Called by the host (forwarded to Kivy) */

/* Queues an event for Kivy's next `kivy_nui_poll_event`. DROP_* strings are
   copied. */
KIVY_NUI_API void kivy_nui_push_event(const KivyNUIEvent *event);

/* Runs Kivy's tick, if Kivy is registered. Called from the host's
   DisplaySync callback. */
KIVY_NUI_API void kivy_nui_tick(double dt);

#ifdef __cplusplus
}
#endif

#endif /* KIVY_NUI_H */
