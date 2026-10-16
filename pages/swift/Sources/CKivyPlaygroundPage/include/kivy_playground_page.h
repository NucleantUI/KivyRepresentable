// The editor page's side of the web playground, imported from the page
// (kivy-playground.wasm-host.mjs): the sources its editors hold.
// `which` is 0 for app.py, 1 for app.kv.

#ifndef KIVY_PLAYGROUND_PAGE_H
#define KIVY_PLAYGROUND_PAGE_H

#ifdef __wasm__
#define KIVY_PLAYGROUND_PAGE_IMPORT(name) __attribute__((import_module("kivy_playground"), import_name(#name)))

/// The source's length in UTF-8 bytes.
KIVY_PLAYGROUND_PAGE_IMPORT(source_length) int kivy_playground_source_length(int which);

/// Copies the source, UTF-8, into `buffer` (its length's worth of bytes).
KIVY_PLAYGROUND_PAGE_IMPORT(source_copy) void kivy_playground_source_copy(int which, char *buffer);
#endif

#endif
