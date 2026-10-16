// Folding on the playground page: the rail folds the editors away so the
// Kivy window gets the width, and each editor's header folds that editor so
// the other gets its height. What is folded is remembered per browser; until
// then, the editors start folded in portrait.

const KEY = 'kivy-playground-folded';

const load = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY));
    if (saved) return saved;
  } catch {}
  return { editors: matchMedia('(orientation: portrait)').matches };
};
const save = (folded) => {
  try { localStorage.setItem(KEY, JSON.stringify(folded)); } catch {}
};

const folded = load();
const editors = document.querySelector('.editors');
const rail = document.getElementById('rail');

const showEditors = () => {
  const open = !folded.editors;
  editors.classList.toggle('collapsed', !open);
  rail.setAttribute('aria-expanded', String(open));
  rail.title = open ? 'Hide the code' : 'Show the code';
  rail.querySelector('.chevron').textContent = open ? '‹' : '›';
};
rail.addEventListener('click', () => {
  folded.editors = !folded.editors;
  showEditors();
  save(folded);
});
showEditors();

for (const pane of document.querySelectorAll('.panes .pane')) {
  const name = pane.dataset.pane;
  const toggle = pane.querySelector('.pane-toggle');
  const show = () => {
    const open = !folded[name];
    pane.classList.toggle('collapsed', !open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.querySelector('.chevron').textContent = open ? '▾' : '▸';
  };
  toggle.addEventListener('click', () => {
    folded[name] = !folded[name];
    show();
    save(folded);
  });
  show();
}
