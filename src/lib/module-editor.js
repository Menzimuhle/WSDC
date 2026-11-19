// Admin → Modules: create, edit, reorder and publish training modules,
// including their practice quizzes, without touching GitHub.
import EasyMDE from 'easymde';
import 'easymde/dist/easymde.min.css';
import 'font-awesome/css/font-awesome.min.css'; // toolbar icons, bundled with the site
import { supabase, esc, toast, path } from './supabase.js';
import { renderMarkdown, slugify } from './modules.js';

const MAX_IMAGE_MB = 5;
let editor = null;   // EasyMDE instance
let dirty = false;


window.addEventListener('beforeunload', (e) => { if (dirty) e.preventDefault(); });

export async function loadModulesPanel(el) {
  if (dirty && !confirm('You have unsaved changes. Leave without saving?')) return;
  dirty = false;
  destroyEditor();
  el.innerHTML = '<p class="muted">Loading…</p>';
  const { data, error } = await supabase.from('training_modules')
    .select('id, slug, title, published, position, quiz, updated_at').order('position').order('id');
  if (error) { el.innerHTML = `<div class="notice notice-bad">${esc(error.message)}</div>`; return; }
  const mods = data ?? [];
  el.innerHTML = `
    <div class="row" style="justify-content:space-between;margin-bottom:12px">
      <p class="muted" style="margin:0">Modules appear on the site in this order. Drafts are visible only to the CA team.</p>
      <button class="btn btn-small" id="mod-new">+ New module</button>
    </div>
    <div class="table-wrap"><table>
      <thead><tr><th>#</th><th>Title</th><th>Status</th><th class="num">Quiz questions</th><th>Last edited</th><th>Order</th><th></th></tr></thead>
      <tbody>${mods.map((m, i) => `<tr>
        <td>${i + 1}</td>
        <td style="white-space:normal;min-width:220px"><strong>${esc(m.title)}</strong></td>
        <td>${m.published ? '<span class="badge badge-good">Published</span>' : '<span class="badge badge-warn">Draft</span>'}</td>
        <td class="num">${(m.quiz || []).length}</td>
        <td>${new Date(m.updated_at).toLocaleDateString()}</td>
        <td><button class="btn btn-ghost btn-small" data-up="${i}" ${i === 0 ? 'disabled' : ''} aria-label="Move up">↑</button>
            <button class="btn btn-ghost btn-small" data-down="${i}" ${i === mods.length - 1 ? 'disabled' : ''} aria-label="Move down">↓</button></td>
        <td class="row" style="flex-wrap:nowrap"><button class="btn btn-small" data-edit="${m.id}">Edit</button>
            <a class="btn btn-ghost btn-small" href="${path('module/?m=' + m.slug)}" target="_blank" rel="noopener">View</a></td>
      </tr>`).join('') || '<tr><td colspan="7" class="muted">No modules yet. Click "New module" to create one.</td></tr>'}
      </tbody></table></div>`;

  el.querySelector('#mod-new').onclick = () => openEditor(el, null, mods.length);
  el.querySelectorAll('[data-edit]').forEach((b) => b.onclick = async () => {
    const { data: m, error: e } = await supabase.from('training_modules').select('*').eq('id', b.dataset.edit).single();
    if (e) return toast(e.message, 'error');
    openEditor(el, m, mods.length);
  });
  const move = async (i, j) => {
    const order = [...mods];
    [order[i], order[j]] = [order[j], order[i]];
    const updates = order.map((m, k) => ({ id: m.id, position: (k + 1) * 10 })).filter((u, k) => order[k].position !== u.position);
    for (const u of updates) {
      const { error: e } = await supabase.from('training_modules').update({ position: u.position }).eq('id', u.id);
      if (e) return toast(e.message, 'error');
    }
    loadModulesPanel(el);
  };
  el.querySelectorAll('[data-up]').forEach((b) => b.onclick = () => move(+b.dataset.up, +b.dataset.up - 1));
  el.querySelectorAll('[data-down]').forEach((b) => b.onclick = () => move(+b.dataset.down, +b.dataset.down + 1));
}

function destroyEditor() {
  if (editor) { try { editor.toTextArea(); } catch { /* ignore */ } editor = null; }
}

function openEditor(el, m, count) {
  destroyEditor();
  const isNew = !m;
  m = m ?? { title: '', summary: '', minutes: null, video_url: '', body: '', quiz: [], published: false, position: (count + 1) * 10 };
  el.innerHTML = `
    <form id="mod-form">
      <div class="row" style="justify-content:space-between;margin-bottom:8px">
        <button type="button" class="btn btn-ghost btn-small" id="mod-back">← All modules</button>
        <span class="muted small">${isNew ? 'New module' : 'Editing module'}</span>
      </div>
      <div class="card">
        <div class="field"><label for="m-title">Title</label><input id="m-title" type="text" required maxlength="140" value="${esc(m.title)}"></div>
        <div class="field"><label for="m-slug">Web address</label>
          <div class="row" style="flex-wrap:nowrap;gap:6px"><span class="muted small" style="white-space:nowrap">…/module/?m=</span>
          <input id="m-slug" type="text" value="${esc(m.slug ?? '')}" ${isNew ? '' : 'readonly'} pattern="[a-z0-9]+(-[a-z0-9]+)*"></div>
          <span class="hint">${isNew ? 'Filled in from the title. Lowercase letters, numbers and dashes only.' : 'Fixed once created, so judges\' saved progress keeps pointing here.'}</span></div>
        <div class="field"><label for="m-summary">One-line summary <span class="hint">(shown in the module list)</span></label><input id="m-summary" type="text" maxlength="240" value="${esc(m.summary)}"></div>
        <div class="row">
          <div class="field" style="width:200px"><label for="m-minutes">Estimated minutes</label><input id="m-minutes" type="number" min="1" value="${m.minutes ?? ''}"></div>
          <div class="field" style="flex:1;min-width:240px"><label for="m-video">Main video <span class="hint">(optional YouTube link, shown at the top)</span></label><input id="m-video" type="text" value="${esc(m.video_url ?? '')}" placeholder="https://youtu.be/…"></div>
        </div>
      </div>

      <div class="card">
        <h3 style="margin-top:0">Lesson content</h3>
        <p class="hint" style="margin-top:-6px">Use the toolbar for headings, bold, lists, quotes, tables, links and images. Click the eye icon to preview. To add more videos, paste a YouTube link on its own line.</p>
        <textarea id="m-body">${esc(m.body)}</textarea>
      </div>

      <div class="card">
        <h3 style="margin-top:0">Practice quiz</h3>
        <p class="hint" style="margin-top:-6px">Judges see the explanation or model answer straight after answering. Practice answers aren't secret, so put placement questions in the Final test instead.</p>
        <div id="q-list"></div>
        <div class="row">
          <button type="button" class="btn btn-ghost btn-small" id="add-mcq">+ Multiple-choice question</button>
          <button type="button" class="btn btn-ghost btn-small" id="add-open">+ Written question with model answer</button>
        </div>
      </div>

      <div class="card row" style="justify-content:space-between;position:sticky;bottom:12px;z-index:3">
        <label class="row" style="font-weight:600"><input type="checkbox" id="m-pub" ${m.published ? 'checked' : ''}> Published (visible to judges)</label>
        <div class="row">
          ${isNew ? '' : '<button type="button" class="btn btn-danger btn-small" id="mod-del">Delete</button>'}
          <button type="submit" class="btn">Save</button>
        </div>
      </div>
    </form>`;

  const $ = (s) => el.querySelector(s);
  if (isNew) {
    let touched = false;
    $('#m-slug').addEventListener('input', () => { touched = true; });
    $('#m-title').addEventListener('input', () => { if (!touched) $('#m-slug').value = slugify($('#m-title').value); });
  }

  editor = new EasyMDE({
    element: $('#m-body'),
    spellChecker: false,
    autoDownloadFontAwesome: false, // icons are bundled (see import above)
    status: ['lines', 'words'],
    minHeight: '320px',
    forceSync: true,
    promptURLs: true,
    uploadImage: true,
    imageMaxSize: MAX_IMAGE_MB * 1024 * 1024,
    imageAccept: 'image/png, image/jpeg, image/gif, image/webp',
    imageUploadFunction: uploadImage,
    previewRender: (md) => renderMarkdown(md),
    previewClass: ['editor-preview', 'prose'],
    toolbar: ['bold', 'italic', 'heading-2', 'heading-3', '|', 'unordered-list', 'ordered-list', 'quote', 'table', 'horizontal-rule', '|',
      'link', 'upload-image', '|', 'undo', 'redo', '|', 'preview', 'side-by-side', 'fullscreen', '|', 'guide'],
  });
  editor.codemirror.on('change', () => { dirty = true; });
  el.querySelectorAll('input, textarea').forEach((i) => i.addEventListener('input', () => { dirty = true; }));

  const qList = $('#q-list');
  (m.quiz || []).forEach((q) => addQuestion(qList, q));
  $('#add-mcq').onclick = () => { addQuestion(qList, { type: 'mcq', question: '', options: ['', '', ''], answer: 0, explanation: '' }); dirty = true; };
  $('#add-open').onclick = () => { addQuestion(qList, { type: 'open', question: '', model_answer: '' }); dirty = true; };

  $('#mod-back').onclick = () => loadModulesPanel(el);
  const del = $('#mod-del');
  if (del) del.onclick = async () => {
    if (!confirm(`Delete "${m.title}"? This can't be undone. Consider unticking "Published" instead.`)) return;
    const { error } = await supabase.from('training_modules').delete().eq('id', m.id);
    if (error) return toast(error.message, 'error');
    dirty = false; toast('Module deleted'); loadModulesPanel(el);
  };

  $('#mod-form').onsubmit = async (e) => {
    e.preventDefault();
    const quiz = readQuiz(qList);
    if (typeof quiz === 'string') return toast(quiz, 'error');
    const row = {
      title: $('#m-title').value.trim(),
      summary: $('#m-summary').value.trim(),
      minutes: Number($('#m-minutes').value) || null,
      video_url: $('#m-video').value.trim() || null,
      body: editor.value(),
      quiz,
      published: $('#m-pub').checked,
    };
    if (!row.title) return toast('Add a title', 'error');
    let res;
    if (isNew) {
      row.slug = slugify($('#m-slug').value || row.title);
      row.position = m.position;
      res = await supabase.from('training_modules').insert(row).select('*').single();
    } else {
      res = await supabase.from('training_modules').update(row).eq('id', m.id).select('*').single();
    }
    if (res.error) {
      const msg = /duplicate key|unique/i.test(res.error.message) ? 'That web address is already used by another module. Change it and save again.' : res.error.message;
      return toast(msg, 'error');
    }
    dirty = false;
    toast(row.published ? 'Saved and published' : 'Saved as draft');
    openEditor(el, res.data, count); // stay in the editor, now in "edit" mode
  };
}

async function uploadImage(file, onSuccess, onError) {
  const safe = file.name.toLowerCase().replace(/[^a-z0-9.]+/g, '-');
  const name = `${Date.now()}-${safe}`;
  const { error } = await supabase.storage.from('training-media').upload(name, file, { contentType: file.type, upsert: false });
  if (error) return onError('Upload failed: ' + error.message);
  const { data } = supabase.storage.from('training-media').getPublicUrl(name);
  onSuccess(data.publicUrl);
}

// ---------- Quiz builder ----------
function addQuestion(list, q) {
  const card = document.createElement('div');
  card.className = 'q-card';
  card.dataset.type = q.type;
  const name = 'c' + Math.random().toString(36).slice(2);
  card.innerHTML = `
    <div class="row" style="justify-content:space-between;margin-bottom:8px">
      <strong class="q-num"></strong> <span class="badge">${q.type === 'mcq' ? 'Multiple choice' : 'Written + model answer'}</span>
      <span class="row" style="margin-left:auto;gap:4px">
        <button type="button" class="btn btn-ghost btn-small" data-act="up" aria-label="Move up">↑</button>
        <button type="button" class="btn btn-ghost btn-small" data-act="down" aria-label="Move down">↓</button>
        <button type="button" class="btn btn-ghost btn-small" data-act="del">Remove</button>
      </span>
    </div>
    <div class="field"><label>Question</label><textarea rows="2" data-f="question">${esc(q.question)}</textarea></div>
    ${q.type === 'mcq' ? `
      <label>Options <span class="hint">(select the correct one)</span></label>
      <div data-f="options"></div>
      <button type="button" class="btn btn-ghost btn-small" data-act="addopt" style="margin-bottom:12px">+ Add option</button>
      <div class="field"><label>Explanation <span class="hint">(shown after answering: why the answer is right, ideally citing the Manual or Rules)</span></label><textarea rows="3" data-f="explanation">${esc(q.explanation || '')}</textarea></div>`
    : `<div class="field"><label>Model answer</label><textarea rows="4" data-f="model_answer">${esc(q.model_answer || '')}</textarea></div>`}`;
  list.appendChild(card);

  const addOpt = (text, checked) => {
    const row = document.createElement('div');
    row.className = 'row opt-row';
    row.style.cssText = 'flex-wrap:nowrap;margin-bottom:6px';
    row.innerHTML = `<input type="radio" name="${name}" ${checked ? 'checked' : ''} aria-label="Correct answer" style="width:auto">
      <input type="text" value="${esc(text)}" placeholder="Option text">
      <button type="button" class="btn btn-ghost btn-small" aria-label="Remove option">✕</button>`;
    row.querySelector('button').onclick = () => { row.remove(); dirty = true; };
    row.querySelectorAll('input').forEach((i) => i.addEventListener('input', () => { dirty = true; }));
    card.querySelector('[data-f="options"]').appendChild(row);
  };
  if (q.type === 'mcq') {
    (q.options || []).forEach((o, i) => addOpt(o, i === Number(q.answer)));
    card.querySelector('[data-act="addopt"]').onclick = () => { addOpt('', false); dirty = true; };
  }
  card.querySelector('[data-act="del"]').onclick = () => { if (confirm('Remove this question?')) { card.remove(); renumber(list); dirty = true; } };
  card.querySelector('[data-act="up"]').onclick = () => { card.previousElementSibling?.before(card); renumber(list); dirty = true; };
  card.querySelector('[data-act="down"]').onclick = () => { card.nextElementSibling?.after(card); renumber(list); dirty = true; };
  card.querySelectorAll('textarea').forEach((t) => t.addEventListener('input', () => { dirty = true; }));
  renumber(list);
}

function renumber(list) {
  list.querySelectorAll('.q-card').forEach((c, i) => { c.querySelector('.q-num').textContent = `Question ${i + 1}`; });
}

/** Returns the quiz array, or an error message string. */
function readQuiz(list) {
  const out = [];
  const cards = [...list.querySelectorAll('.q-card')];
  for (let i = 0; i < cards.length; i++) {
    const c = cards[i];
    const question = c.querySelector('[data-f="question"]').value.trim();
    if (!question) return `Question ${i + 1} is empty. Fill it in or remove it.`;
    if (c.dataset.type === 'mcq') {
      const rows = [...c.querySelectorAll('.opt-row')];
      const options = [], texts = rows.map((r) => r.querySelector('input[type=text]').value.trim());
      let answer = -1;
      rows.forEach((r, k) => {
        if (!texts[k]) return;
        if (r.querySelector('input[type=radio]').checked) answer = options.length;
        options.push(texts[k]);
      });
      if (options.length < 2) return `Question ${i + 1} needs at least two options.`;
      if (answer < 0) return `Question ${i + 1}: select the correct option.`;
      out.push({ type: 'mcq', question, options, answer, explanation: c.querySelector('[data-f="explanation"]').value.trim() });
    } else {
      out.push({ type: 'open', question, model_answer: c.querySelector('[data-f="model_answer"]').value.trim() });
    }
  }
  return out;
}
