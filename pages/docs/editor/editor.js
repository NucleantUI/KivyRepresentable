// The playground page: Monaco editors for app.kv and app.py, and
// WebPlayground (a KivyAppView running kivy_playground) beside them. The
// editors' sources live in `globalThis.kivyPlayground`, where the app reads
// them (kivy-playground.wasm-host.mjs); an edit asks the app to run them
// again (`kivy_playground_reload`) once typing pauses.

import { runNucleantApp } from './app/nucleant-app.js';

const DEFAULTS = './app/resources/WebPlayground_WebPlayground.resources/site_packages/kivy_playground/default/';
const RELOAD_DELAY = 600;

const status = document.getElementById('status');
const fetchText = async (url) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`cannot load ${url} (${response.status})`);
  return response.text();
};

const [py, kv, monaco] = await Promise.all([
  fetchText(DEFAULTS + 'app.py'),
  fetchText(DEFAULTS + 'app.kv'),
  loadMonaco(),
]);
globalThis.kivyPlayground = { py, kv };

registerKv(monaco);
const dark = matchMedia('(prefers-color-scheme: dark)');
const options = {
  automaticLayout: true,
  minimap: { enabled: false },
  fontSize: 13,
  tabSize: 4,
  insertSpaces: true,
  scrollBeyondLastLine: false,
  theme: dark.matches ? 'vs-dark' : 'vs',
};
const editors = {
  kv: monaco.editor.create(document.getElementById('kv'), { ...options, value: kv, language: 'kv' }),
  py: monaco.editor.create(document.getElementById('py'), { ...options, value: py, language: 'python' }),
};
dark.addEventListener('change', (event) => monaco.editor.setTheme(event.matches ? 'vs-dark' : 'vs'));

// The app, and a reload once it runs: before then, edits only change what
// it will start with.
let app = null;
let edited = false;
let timer = 0;
const reload = () => {
  if (!app) return;
  status.textContent = 'Reloading…';
  app.dom.call('kivy_playground_reload').then(() => { status.textContent = 'Running'; });
};
for (const [name, editor] of Object.entries(editors)) {
  editor.onDidChangeModelContent(() => {
    globalThis.kivyPlayground[name] = editor.getValue();
    edited = true;
    clearTimeout(timer);
    timer = setTimeout(reload, RELOAD_DELAY);
  });
}

status.textContent = 'Starting Python…';
try {
  app = await runNucleantApp({
    wasm: './app/WebPlayground.wasm.gz',
    resources: './app/resources.json',
    zoneinfo: './app/zoneinfo.bin',
    container: document.getElementById('app'),
  });
  status.textContent = 'Running';
  if (edited) reload();
} catch (error) {
  status.textContent = `Could not start: ${error.message}`;
  console.error(error);
}

/** Monaco, from its AMD loader (index.html loads loader.js). */
function loadMonaco() {
  return new Promise((resolve, reject) => {
    globalThis.require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } });
    globalThis.require(['vs/editor/editor.main'], () => resolve(globalThis.monaco), reject);
  });
}

/** Kivy's language: rules, properties, canvas instructions, Python values. */
function registerKv(monaco) {
  monaco.languages.register({ id: 'kv', extensions: ['.kv'], aliases: ['KV', 'kv'] });
  monaco.languages.setLanguageConfiguration('kv', {
    comments: { lineComment: '#' },
    brackets: [['(', ')'], ['[', ']'], ['{', '}']],
    autoClosingPairs: [
      { open: '(', close: ')' }, { open: '[', close: ']' }, { open: '{', close: '}' },
      { open: "'", close: "'" }, { open: '"', close: '"' },
    ],
    onEnterRules: [{ beforeText: /:\s*$/, action: { indentAction: monaco.languages.IndentAction.Indent } }],
  });
  monaco.languages.setMonarchTokensProvider('kv', {
    keywords: ['True', 'False', 'None', 'and', 'or', 'not', 'if', 'else', 'in', 'is', 'lambda'],
    tokenizer: {
      root: [
        [/^\s*#:.*$/, 'keyword'],                                   // #:import, #:set
        [/#.*$/, 'comment'],
        [/^\s*<[^>]+>:?/, 'type'],                                  // <Rule>: / <Dyn@Base>:
        [/^(\s*)([A-Z][\w.]*)(:)/, ['', 'type', 'delimiter']],      // Widget:
        [/^(\s*)(canvas(?:\.before|\.after)?)(:)/, ['', 'keyword', 'delimiter']],
        [/^(\s*)(on_\w+)(:)/, ['', 'keyword', 'delimiter']],        // on_press:
        [/^(\s*)(\w+)(:)/, ['', 'attribute.name', 'delimiter']],    // property:
        { include: 'value' },
      ],
      value: [
        [/"([^"\\]|\\.)*"/, 'string'],
        [/'([^'\\]|\\.)*'/, 'string'],
        [/\d+(\.\d+)?/, 'number'],
        [/\b(self|root|app|ids)\b/, 'variable.predefined'],
        [/[a-zA-Z_]\w*/, { cases: { '@keywords': 'keyword', '@default': 'identifier' } }],
        [/[()[\]{},.:]/, 'delimiter'],
      ],
    },
  });
}
