// Renders a practice quiz and saves the best score.
import { esc } from './supabase.js';
import { loadProgress, saveProgress } from './progress.js';

const LETTERS = 'ABCDEFGHIJ';

export function renderQuiz(root, slug, quiz) {
  const items = (quiz || []).filter((q) => q && q.question);
  if (!items.length) { root.innerHTML = ''; return; }
  const total = items.filter((q) => q.type === 'mcq').length;

  root.innerHTML = `
    <section class="card" id="practice">
      <h2 style="margin-top:0">Practice quiz</h2>
      <p class="muted">Practice only, so nothing here counts towards placement. After each answer you'll see what we expected and why.</p>
      ${items.map((q, i) => q.type === 'mcq' ? `
        <div class="quiz-q" data-type="mcq" data-answer="${Number(q.answer)}">
          <h3>${i + 1}. ${esc(q.question)}</h3>
          ${(q.options || []).map((o, j) => `<button type="button" class="opt" data-i="${j}"><span class="letter">${LETTERS[j]}</span><span>${esc(o)}</span></button>`).join('')}
          <div class="explain" hidden><strong></strong><span class="prompt">${esc(q.explanation || '')}</span></div>
        </div>` : `
        <div class="quiz-q" data-type="open">
          <h3>${i + 1}. ${esc(q.question)}</h3>
          <textarea aria-label="Your answer" placeholder="Write your answer, then compare it with the model answer."></textarea>
          <div class="row" style="margin-top:8px"><button type="button" class="btn btn-ghost btn-small reveal">Show model answer</button></div>
          <div class="explain" hidden><strong>Model answer</strong><span class="prompt">${esc(q.model_answer || '')}</span></div>
        </div>`).join('')}
      <div class="notice" id="quiz-result" hidden></div>
      <div class="row"><button type="button" class="btn btn-ghost btn-small" id="quiz-reset">Try again</button></div>
    </section>`;

  let correct = 0, answered = 0;
  root.querySelectorAll('.quiz-q[data-type="mcq"]').forEach((qEl) => {
    const answer = Number(qEl.dataset.answer);
    const opts = qEl.querySelectorAll('.opt');
    opts.forEach((btn) => btn.addEventListener('click', () => {
      const pick = Number(btn.dataset.i);
      opts.forEach((b) => { b.disabled = true; });
      opts[answer]?.classList.add('correct');
      if (pick !== answer) btn.classList.add('wrong'); else correct++;
      const ex = qEl.querySelector('.explain');
      ex.querySelector('strong').textContent = pick === answer ? 'Correct.' : 'Not quite.';
      ex.hidden = false;
      if (++answered === total) finish();
    }));
  });
  root.querySelectorAll('.reveal').forEach((btn) => btn.addEventListener('click', () => {
    const ex = btn.closest('.quiz-q').querySelector('.explain');
    ex.hidden = !ex.hidden;
    btn.textContent = ex.hidden ? 'Show model answer' : 'Hide model answer';
  }));

  async function finish() {
    const out = root.querySelector('#quiz-result');
    out.hidden = false;
    const good = correct / total >= 0.8;
    out.className = 'notice ' + (good ? 'notice-good' : 'notice-warn');
    out.textContent = `You got ${correct} of ${total} multiple-choice questions right.` +
      (good ? ' Nice work.' : ' Re-read the module and try again.');
    const prev = (await loadProgress())[slug];
    if (!prev || (prev.practice_score ?? -1) < correct) await saveProgress(slug, { practice_score: correct, practice_total: total });
  }

  root.querySelector('#quiz-reset').addEventListener('click', () => {
    correct = 0; answered = 0;
    root.querySelectorAll('.opt').forEach((b) => { b.disabled = false; b.classList.remove('correct', 'wrong'); });
    root.querySelectorAll('.explain').forEach((e) => { e.hidden = true; });
    root.querySelectorAll('.reveal').forEach((b) => { b.textContent = 'Show model answer'; });
    root.querySelector('#quiz-result').hidden = true;
    root.querySelector('#practice').scrollIntoView({ behavior: 'smooth' });
  });
}
