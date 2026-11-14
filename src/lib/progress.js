// Trainee identity + training progress.
// Judges don't need an emailed link for training: the first time they arrive
// they fill in their details and get a guest account in the background, so
// progress is saved to the database (and visible to the CA team) and picks up
// where they left off on the same browser.
// In preview mode (Supabase not connected) progress falls back to this browser.
import { supabase } from './supabase.js';

const LOCAL_KEY = 'wsdc-training-progress';
const localAll = () => { try { return JSON.parse(localStorage.getItem(LOCAL_KEY) || '{}') || {}; } catch { return {}; } };
const localSave = (all) => { try { localStorage.setItem(LOCAL_KEY, JSON.stringify(all)); } catch { /* ignore */ } };

/** Returns { user, profile } for the current visitor, or null. */
export async function currentTrainee() {
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  const user = data.session?.user;
  if (!user) return null;
  const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).maybeSingle();
  return { user, profile };
}

/** Creates a guest account (if needed) and stores the trainee's details. */
export async function startTraining({ full_name, email, nation }) {
  let { data } = await supabase.auth.getSession();
  if (!data.session) {
    const res = await supabase.auth.signInAnonymously();
    if (res.error) throw res.error;
    data = { session: res.data.session };
  }
  const id = data.session.user.id;
  const { error } = await supabase.from('profiles')
    .update({ full_name, email: email.toLowerCase(), nation: nation || null }).eq('id', id);
  if (error) throw error;
}

/** Map of module_slug → { completed_at, practice_score, practice_total, updated_at } */
export async function loadProgress() {
  if (!supabase) return localAll();
  const t = await currentTrainee();
  if (!t) return {};
  const { data } = await supabase.from('module_progress').select('module_slug, completed_at, practice_score, practice_total, updated_at');
  return Object.fromEntries((data ?? []).map((r) => [r.module_slug, r]));
}

/** Saves progress for one module. Only provided fields are changed. */
export async function saveProgress(slug, patch) {
  const updated_at = new Date().toISOString();
  if (!supabase) {
    const all = localAll();
    all[slug] = { ...(all[slug] || {}), ...patch, updated_at };
    localSave(all);
    return;
  }
  const { data } = await supabase.auth.getSession();
  const user = data.session?.user;
  if (!user) return;
  await supabase.from('module_progress').upsert(
    { user_id: user.id, module_slug: slug, ...patch, updated_at }, { onConflict: 'user_id,module_slug' });
}

/** Pick the module to continue: the most recently opened unfinished one, else the first unfinished. */
export function nextModule(modules, progress) {
  const unfinished = modules.filter((m) => !progress[m.slug]?.completed_at);
  if (!unfinished.length) return null;
  const opened = unfinished.filter((m) => progress[m.slug]).sort((a, b) =>
    String(progress[b.slug].updated_at).localeCompare(String(progress[a.slug].updated_at)));
  return opened[0] ?? unfinished[0];
}
