#include "kivy_nui.h"

#include <stdlib.h>
#include <string.h>

/* Everything here runs on the main thread (see kivy_nui.h), so no locks. */

static KivyNUIHost g_host;
static bool g_has_host = false;

static KivyNUIKivy g_kivy;
static bool g_has_kivy = false;

/* MARK: - Registration */

void kivy_nui_set_host(const KivyNUIHost *host) {
    if (host) {
        g_host = *host;
        g_has_host = true;
    } else {
        memset(&g_host, 0, sizeof g_host);
        g_has_host = false;
    }
}

bool kivy_nui_is_hosted(void) {
    return g_has_host;
}

void kivy_nui_set_kivy(const KivyNUIKivy *kivy) {
    if (kivy) {
        g_kivy = *kivy;
        g_has_kivy = true;
    } else {
        memset(&g_kivy, 0, sizeof g_kivy);
        g_has_kivy = false;
    }
}

/* MARK: - Kivy -> host */

const KivyNUIGL *kivy_nui_gl(void) {
    return g_has_host ? g_host.gl : NULL;
}

bool kivy_nui_create_gl_context(void) {
    return g_host.create_gl_context ? g_host.create_gl_context(g_host.context) : false;
}

void kivy_nui_destroy_gl_context(void) {
    if (g_host.destroy_gl_context) g_host.destroy_gl_context(g_host.context);
}

void kivy_nui_present(void) {
    if (g_host.present) g_host.present(g_host.context);
}

void kivy_nui_get_window_metrics(KivyNUIWindowMetrics *out) {
    if (!out) return;
    memset(out, 0, sizeof *out);
    if (g_host.get_window_metrics) g_host.get_window_metrics(g_host.context, out);
}

void kivy_nui_set_title(const char *utf8) {
    if (g_host.set_title) g_host.set_title(g_host.context, utf8 ? utf8 : "");
}

void kivy_nui_set_system_cursor(KivyNUICursor cursor) {
    if (g_host.set_system_cursor) g_host.set_system_cursor(g_host.context, cursor);
}

void kivy_nui_set_cursor_visible(bool visible) {
    if (g_host.set_cursor_visible) g_host.set_cursor_visible(g_host.context, visible);
}

void kivy_nui_show_keyboard(void) {
    if (g_host.show_keyboard) g_host.show_keyboard(g_host.context);
}

void kivy_nui_hide_keyboard(void) {
    if (g_host.hide_keyboard) g_host.hide_keyboard(g_host.context);
}

void kivy_nui_request_close(void) {
    if (g_host.request_close) g_host.request_close(g_host.context);
}

/* MARK: - Event queue (host pushes, Kivy polls) */

/* A growable ring of events. DROP_* strings are copied on push; the one
   handed out by the last poll is kept alive until the next poll. */
static KivyNUIEvent *g_events = NULL;
static size_t g_capacity = 0;
static size_t g_head = 0;
static size_t g_count = 0;
static char *g_polled_drop = NULL;

static bool is_drop_with_text(KivyNUIEventType type) {
    return type == KIVY_NUI_EVENT_DROP_FILE || type == KIVY_NUI_EVENT_DROP_TEXT;
}

static bool grow(void) {
    size_t capacity = g_capacity ? g_capacity * 2 : 64;
    KivyNUIEvent *events = malloc(capacity * sizeof *events);
    if (!events) return false;
    for (size_t i = 0; i < g_count; i++) {
        events[i] = g_events[(g_head + i) % g_capacity];
    }
    free(g_events);
    g_events = events;
    g_capacity = capacity;
    g_head = 0;
    return true;
}

void kivy_nui_push_event(const KivyNUIEvent *event) {
    if (!event || event->type == KIVY_NUI_EVENT_NONE) return;
    if (g_count == g_capacity && !grow()) return;

    KivyNUIEvent copy = *event;
    if (is_drop_with_text(copy.type)) {
        copy.drop.utf8 = strdup(copy.drop.utf8 ? copy.drop.utf8 : "");
        if (!copy.drop.utf8) return;
    }
    if (copy.type == KIVY_NUI_EVENT_TEXT_INPUT || copy.type == KIVY_NUI_EVENT_TEXT_EDIT) {
        copy.text.utf8[KIVY_NUI_TEXT_SIZE - 1] = '\0';
    }
    g_events[(g_head + g_count) % g_capacity] = copy;
    g_count++;
}

bool kivy_nui_poll_event(KivyNUIEvent *out) {
    free(g_polled_drop);
    g_polled_drop = NULL;

    if (g_count == 0 || !out) return false;
    *out = g_events[g_head];
    g_head = (g_head + 1) % g_capacity;
    g_count--;

    if (is_drop_with_text(out->type)) {
        g_polled_drop = (char *)out->drop.utf8;
    }
    return true;
}

/* MARK: - Host -> Kivy */

void kivy_nui_tick(double dt) {
    if (g_has_kivy && g_kivy.tick) g_kivy.tick(g_kivy.context, dt);
}
