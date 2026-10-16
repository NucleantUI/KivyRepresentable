// kivy-keyboard.wasm-host.mjs — the page's side of Kivy's keyboard,
// served with KivyRepresentable's resources (Web/nucleant-app.js loads it as
// a host).
//
// A canvas brings up no on-screen keyboard, so the page keeps a text field
// out of sight: Kivy asking for the keyboard (a TextInput focused) focuses
// it, letting it go blurs it. What is typed into the field is queued as
// inputs the app reads each frame (CKivyKeyboardPage/include/
// kivy_keyboard_page.h): `t` and the text typed, or `d` / `u`, a key's SDL
// keycode, a space and its KMOD_* bits.
//
// iOS brings the keyboard up only for a focus made while handling a touch,
// and Kivy asks on its next frame, after the press: so the touch's end
// focuses the field too, while Kivy wants the keyboard.

const SDL_KEYS = {
  Backspace: 8, Tab: 9, Enter: 13, Escape: 27, Delete: 127,
  ArrowRight: 1073741903, ArrowLeft: 1073741904, ArrowDown: 1073741905, ArrowUp: 1073741906,
  Home: 1073741898, PageUp: 1073741899, End: 1073741901, PageDown: 1073741902,
};

// The field always holds this, so a backspace has something to delete
// even with nothing typed.
const KEEP = ' ';

export async function prepare() {
  let memory = null;
  let wanted = false;
  let composing = false;
  const inputs = [];
  const encoder = new TextEncoder();

  const field = document.createElement('textarea');
  for (const [name, value] of Object.entries({
    autocapitalize: 'off', autocomplete: 'off', autocorrect: 'off', spellcheck: 'false',
    'aria-hidden': 'true', tabindex: '-1',
  })) field.setAttribute(name, value);
  // 16px: iOS zooms the page into a field with smaller text.
  field.style.cssText = 'position:fixed;left:0;bottom:0;width:1px;height:1px;padding:0;border:0;'
    + 'opacity:0;font-size:16px;resize:none;pointer-events:none;caret-color:transparent;';
  const reset = () => {
    field.value = KEEP;
    field.setSelectionRange(KEEP.length, KEEP.length);
  };
  reset();
  document.body.append(field);

  const mod = (event) => (event.shiftKey ? 0x0001 : 0) | (event.ctrlKey ? 0x0040 : 0)
    | (event.altKey ? 0x0100 : 0) | (event.metaKey ? 0x0400 : 0);
  const key = (keycode, modifiers = 0) => inputs.push(`d${keycode} ${modifiers}`, `u${keycode} ${modifiers}`);
  const typed = (text) => {
    // A line break the field took (no keydown came for it) is Kivy's return.
    text.split('\n').forEach((line, index) => {
      if (index > 0) key(SDL_KEYS.Enter);
      // In pieces well inside what the app reads at once (a paste).
      const characters = Array.from(line);
      for (let start = 0; start < characters.length; start += 512) {
        inputs.push(`t${characters.slice(start, start + 512).join('')}`);
      }
    });
  };

  // The keys that edit rather than type, and shortcuts, as keys. A paste
  // is left to the field, and arrives as typed text.
  const keycode = (event) => {
    if (event.key in SDL_KEYS) return SDL_KEYS[event.key];
    if ((event.ctrlKey || event.metaKey) && event.key.length === 1 && event.key.toLowerCase() !== 'v') {
      return event.key.toLowerCase().codePointAt(0);
    }
    return null;
  };
  field.addEventListener('keydown', (event) => {
    if (event.isComposing) return;
    const code = keycode(event);
    if (code === null) return;
    event.preventDefault();
    inputs.push(`d${code} ${mod(event)}`);
  });
  field.addEventListener('keyup', (event) => {
    const code = keycode(event);
    if (code !== null) inputs.push(`u${code} ${mod(event)}`);
  });
  field.addEventListener('compositionstart', () => { composing = true; });
  field.addEventListener('compositionend', () => { composing = false; take(); });
  field.addEventListener('input', () => { if (!composing) take(); });
  function take() {
    const value = field.value;
    if (!value.startsWith(KEEP)) {
      // KEEP itself went: a backspace the keydown didn't report.
      if (value.length < KEEP.length) key(SDL_KEYS.Backspace);
      else typed(value);
    } else if (value.length > KEEP.length) {
      typed(value.slice(KEEP.length));
    }
    reset();
  }

  const focus = () => {
    if (wanted && document.activeElement !== field) field.focus({ preventScroll: true });
  };
  for (const type of ['touchend', 'pointerup']) document.addEventListener(type, focus, true);

  return {
    imports: {
      kivy_keyboard: {
        show: () => {
          wanted = true;
          focus();
        },
        hide: () => {
          wanted = false;
          if (document.activeElement === field) field.blur();
        },
        next: (buffer, capacity) => {
          if (!inputs.length) return -1;
          let bytes = encoder.encode(inputs.shift());
          if (bytes.length > capacity) bytes = bytes.subarray(0, capacity);
          new Uint8Array(memory.buffer).set(bytes, buffer >>> 0);
          return bytes.length;
        },
      },
    },
    attach(instance) {
      memory = instance.exports.memory;
    },
  };
}
