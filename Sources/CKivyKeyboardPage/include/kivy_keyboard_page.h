// The page's on-screen keyboard, imported from the page
// (kivy-keyboard.wasm-host.mjs, a KivyRepresentable resource).

#ifndef KIVY_KEYBOARD_PAGE_H
#define KIVY_KEYBOARD_PAGE_H

#ifdef __wasm__
#define KIVY_KEYBOARD_PAGE_IMPORT(name) __attribute__((import_module("kivy_keyboard"), import_name(#name)))

/// Kivy asked for the keyboard: the page focuses its text field.
KIVY_KEYBOARD_PAGE_IMPORT(show) void kivy_keyboard_show(void);

/// Kivy let the keyboard go.
KIVY_KEYBOARD_PAGE_IMPORT(hide) void kivy_keyboard_hide(void);

/// Copies the oldest input the field took, UTF-8, into `buffer` and drops
/// it; its length, or -1 when there is none. One input is `t` and the text
/// typed, or `d` (down) / `u` (up), a key's SDL keycode, a space and its
/// KMOD_* bits — `d8 0` is backspace.
KIVY_KEYBOARD_PAGE_IMPORT(next) int kivy_keyboard_next(char *buffer, int capacity);
#endif

#endif
