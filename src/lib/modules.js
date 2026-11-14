// Training modules are stored in Supabase (table training_modules) so the CA
// team can edit them from Admin → Modules.
import { marked } from 'marked';
import DOMPurify from 'dompurify';
import { supabase, youtubeEmbed } from './supabase.js';

const LIST_FIELDS = 'id, slug, title, summary, minutes, position, published, quiz';

/** Published modules in order (admins also get drafts if includeDrafts). */
export async function fetchModules({ includeDrafts = false } = {}) {
  if (!supabase) return [];
  let q = supabase.from('training_modules').select(LIST_FIELDS).order('position').order('id');
  if (!includeDrafts) q = q.eq('published', true);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
}

export async function fetchModule(slug) {
  if (!supabase) return null;
  const { data, error } = await supabase.from('training_modules').select('*').eq('slug', slug).maybeSingle();
  if (error) throw error;
  return data;
}

marked.setOptions({ gfm: true, breaks: false });

/**
 * Markdown → safe HTML. A YouTube link on its own line becomes an embedded
 * video, so CAs can add several videos anywhere in a module.
 */
export function renderMarkdown(md) {
  const html = DOMPurify.sanitize(marked.parse(md || ''), { ADD_ATTR: ['target'] });
  const box = document.createElement('div');
  box.innerHTML = html;
  box.querySelectorAll('p').forEach((p) => {
    const only = p.childNodes.length === 1 ? p.firstChild : null;
    const url = only?.nodeName === 'A' ? only.getAttribute('href') : only?.nodeType === 3 ? only.textContent.trim() : null;
    const embed = youtubeEmbed(url);
    if (embed) p.outerHTML = videoHtml(embed, 'Video');
  });
  box.querySelectorAll('a[href^="http"]').forEach((a) => { a.target = '_blank'; a.rel = 'noopener'; });
  return box.innerHTML;
}

export function videoHtml(embedUrl, title) {
  const t = String(title).replace(/"/g, '&quot;');
  return `<div class="video"><iframe src="${embedUrl}" title="${t}" loading="lazy" allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen></iframe></div>`;
}

/** Turn a title into a URL-friendly slug. */
export function slugify(s) {
  return String(s).toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'module';
}
