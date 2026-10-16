// kivy-playground.wasm-host.mjs — the editor page's side of WebPlayground,
// served with the app's resources (Web/nucleant-app.js loads it as a host).
//
// The page keeps its editors' sources in `globalThis.kivyPlayground`
// ({ py, kv }) and calls the app's `kivy_playground_reload` export when they
// change; the app reads them back through these imports
// (CKivyPlaygroundPage/include/kivy_playground_page.h).

export async function prepare() {
  let memory = null;
  const encoder = new TextEncoder();
  const source = (which) => {
    const sources = globalThis.kivyPlayground ?? {};
    return encoder.encode((which === 0 ? sources.py : sources.kv) ?? '');
  };
  return {
    imports: {
      kivy_playground: {
        source_length: (which) => source(which).length,
        source_copy: (which, buffer) => {
          new Uint8Array(memory.buffer).set(source(which), buffer >>> 0);
        },
      },
    },
    attach(instance) {
      memory = instance.exports.memory;
    },
  };
}
