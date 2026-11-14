-- =====================================================================
-- WSDC Judge Training – training modules (edited on the website)
-- Run AFTER schema.sql: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run: existing modules are left untouched.
--
-- Modules and their practice quizzes live here so CAs can create and edit
-- them from Admin → Modules, with no GitHub involved. Practice-quiz answers
-- are readable by anyone (they're for practice). Final-test answers stay in
-- the separate, locked final_questions table.
-- =====================================================================

create table if not exists public.training_modules (
  id          bigint generated always as identity primary key,
  slug        text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title       text not null,
  summary     text not null default '',
  minutes     int check (minutes is null or minutes > 0),
  video_url   text,
  body        text not null default '',      -- Markdown
  quiz        jsonb not null default '[]',   -- [{type:'mcq',question,options,answer,explanation} | {type:'open',question,model_answer}]
  position    int not null default 0,
  published   boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);

alter table public.training_modules enable row level security;
grant select on public.training_modules to anon, authenticated;

drop policy if exists "modules: read published" on public.training_modules;
create policy "modules: read published" on public.training_modules
  for select to anon, authenticated using (published or public.is_admin());

drop policy if exists "modules: admin write" on public.training_modules;
create policy "modules: admin write" on public.training_modules
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.touch_training_module()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists training_modules_touch on public.training_modules;
create trigger training_modules_touch before insert or update on public.training_modules
  for each row execute function public.touch_training_module();

-- ---------- Images for modules (Supabase Storage) ----------------------
insert into storage.buckets (id, name, public)
values ('training-media', 'training-media', true)
on conflict (id) do nothing;

-- Public bucket: anyone can view images by URL. Admins can list/upload/replace/delete.
drop policy if exists "training-media: admin read" on storage.objects;
create policy "training-media: admin read" on storage.objects
  for select to authenticated using (bucket_id = 'training-media' and public.is_admin());
drop policy if exists "training-media: admin upload" on storage.objects;
create policy "training-media: admin upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'training-media' and public.is_admin());
drop policy if exists "training-media: admin update" on storage.objects;
create policy "training-media: admin update" on storage.objects
  for update to authenticated using (bucket_id = 'training-media' and public.is_admin());
drop policy if exists "training-media: admin delete" on storage.objects;
create policy "training-media: admin delete" on storage.objects
  for delete to authenticated using (bucket_id = 'training-media' and public.is_admin());

-- ---------- Starter modules --------------------------------------------
insert into public.training_modules (slug, title, summary, minutes, body, quiz, position, published) values (
  'wsdc-format', $m$How a WSDC debate works$m$, $m$Teams, speeches, timings, Points of Information and what the motion asks each side to prove.$m$, 15,
  $m$## The shape of the debate

A WSDC debate has **two teams**: Proposition, which supports the motion, and Opposition, which opposes it. Each team can bring up to five members to prepare together, but **three speak** in any one debate.

Speeches alternate between the sides:

| Order | Speech | Time |
|---|---|---|
| 1 | First Proposition (1P) | 8 min |
| 2 | First Opposition (1O) | 8 min |
| 3 | Second Proposition (2P) | 8 min |
| 4 | Second Opposition (2O) | 8 min |
| 5 | Third Proposition (3P) | 8 min |
| 6 | Third Opposition (3O) | 8 min |
| 7 | Opposition Reply | 4 min |
| 8 | Proposition Reply | 4 min |

Reply speeches come in **reverse order**: Opposition first, Proposition last. A reply can be given by the first or second speaker, never the third.

> **Grace period.** The Rules don't mention one, but the accepted norm is 15 seconds after time runs out. Material delivered after that isn't credited.

## Points of Information

Between the **first and seventh minute** of each substantive speech, members of the other team may offer Points of Information (POIs): short questions or statements of **no more than 15 seconds**.

- The speaker may decline a POI, or accept it at the end of their sentence.
- As a general rule, speakers should accept **at least two**.
- The opposing team shouldn't badger. As a guide, no POI should be offered within 20 seconds of the last offer.
- How a speaker answers a POI counts in **their** speech mark. Offering good POIs counts for the speaker who offers them.

## What the motion asks

Every motion starts with "This House…", and the wording tells you what each side has to prove. In short:

- **This House would X**: a policy debate. Proposition shows that its version of X (its *model*) is better than the world Opposition defends.
- **This House believes that X should Y**: a policy debate from a neutral standpoint, with a specific actor.
- **This House supports / opposes / regrets / prefers…**: an analysis debate about the world as it is, or as it likely would have been. There's no modelling.
- **This House, as X, would Y**: an actor debate, judged on X's interests.

Later modules go deeper into each type. For now, remember that **the motion sets the burden**, and your job is to decide which team better met it.

## Your role as a judge

You mark each speech for **Content (40%)**, **Style (40%)** and **Strategy (20%)**, and decide which team won. You do this as an *ordinary intelligent person*: informed, open-minded, and not bringing in your own views or specialist knowledge.
$m$,
  $q$[
 {
  "type": "mcq",
  "question": "How long is a reply speech, and who may give it?",
  "options": [
   "4 minutes, by the first or second speaker",
   "4 minutes, by any of the three speakers",
   "8 minutes, by the third speaker",
   "3 minutes, by the first speaker only"
  ],
  "answer": 0,
  "explanation": "Reply speeches are 4 minutes and may be given by the first or second speaker, never the third (Rules, Schedule 1 §11.2). The Opposition reply comes first and the Proposition reply closes the debate."
 },
 {
  "type": "mcq",
  "question": "When can Points of Information be offered?",
  "options": [
   "At any time during any speech",
   "Between the first and seventh minute of a substantive speech",
   "Only during the second speeches",
   "During reply speeches only"
  ],
  "answer": 1,
  "explanation": "POIs are offered between the first and seventh minutes of the 8-minute substantive speeches (Schedule 1 §13.1). There are no POIs in reply speeches. Each POI should last no longer than 15 seconds."
 },
 {
  "type": "mcq",
  "question": "As a general rule, how many POIs should a speaker accept?",
  "options": [
   "None, accepting is optional",
   "Exactly one",
   "At least two",
   "As many as are offered"
  ],
  "answer": 2,
  "explanation": "The Rules say that as a general rule a speaker should accept at least 2 POIs (Schedule 1 §15.3). Accepting far more risks losing control of the speech. Refusing all POIs isn't banned, but it can be costly, especially in close debates."
 },
 {
  "type": "mcq",
  "question": "A team has 5 members. How many can speak in a single debate?",
  "options": [
   "All five",
   "Four, one of whom gives the reply",
   "Three",
   "Two plus a reply speaker"
  ],
  "answer": 2,
  "explanation": "A team can have up to 5 members who all prepare together, but only 3 speak in each debate (Rules 4.1 and 5.2). One of the first two speakers also gives the reply."
 },
 {
  "type": "open",
  "question": "In one or two sentences, explain what the Proposition must show in a \"This House would X\" motion.",
  "model_answer": "Proposition must show that implementing their version of the policy (their model) is better than whatever world the Opposition supports: the status quo, a countermodel, or a range of alternatives. 'Better' is itself something the teams can debate."
 }
]$q$::jsonb,
  1, true)
on conflict (slug) do nothing;

insert into public.training_modules (slug, title, summary, minutes, body, quiz, position, published) values (
  'new-material', $m$New material in third and reply speeches$m$, $m$What later speakers may and may not add, and how to judge late or new material fairly.$m$, 25,
  $m$Later speeches are where most "was that new?" disputes happen. This module covers what third and reply speakers are allowed to add, so you neither over-credit new material nor wrongly dismiss legitimate development.

## Third speeches

The third speaker's main job is to **respond to what has gone before**: answer the other team's core arguments and their core challenges to your own case. Most good thirds organise the debate into **2–4 clashes** rather than going argument by argument.

### What third speakers should do

- **New rebuttal.** A third speaker with no new rebuttal isn't doing their job. It can be direct refutation or weighing, and can be the first response to a particular claim.
- **Develop existing rebuttal**, especially as the other side rebuilds its arguments.
- **Develop their own team's arguments**: new reasoning, new impacts based on existing analysis, new illustrations. This is fine as long as it can be traced back to earlier material in the debate.

### What third speakers may not do

- **Introduce a new argument**: a logically independent reason that could carry the case on its own even if every earlier speech were ignored. That stays true when it's dressed up as weighing.
- **Introduce new, unanalysed alternatives** that weren't raised earlier (unless responding to an alternative the other side pushed).

> **About the Rules.** Schedule 1 §9.2–9.3 lets a third speaker present a small part of the case **if the first speaker announced it in the case division**. In practice this almost never happens: material that late gets little development and takes time away from responding. If it does happen and was announced, it's permitted, and you can judge how well it was developed.

### Late is not the same as new

Whether material is "late" is a question of **strategy**, not the rules. Late material is allowed but tends to be weaker, because:

- it may be the first response to an argument that has been reinforced over several speeches, so it can't remove the whole argument;
- it's squeezed into the end of the speech;
- it lands hastily without room to develop.

If 3O responds to a 1P argument that 1O and 2O ignored, the response is allowed and **may win that clash**. But it doesn't erase the earlier neglect. Ask:

1. Does the response fully neutralise the argument?
2. Does Proposition still hold uncontested ground elsewhere?

Then reflect the delayed response in the first and second speakers' marks.

## Reply speeches

A reply speech is **retrospective**. Think of it as the speaker explaining why a judge should give their team the debate. Replies should add to the judge's *understanding* of the debate, not to the team's *case*.

| Allowed and encouraged | Not allowed |
|---|---|
| New **weighing**: why some clashes or sub-clashes matter more | New **arguments** |
| New **observations**: dropped arguments, contradictions, unmet burdens, rules issues | New **rebuttal** or responses |
| New **examples** that illustrate an existing argument | New mechanisms or impacts that significantly expand an argument |

> **About the Rules.** Schedule 1 §11.4–11.5 bans new parts of the case and new arguments, and expressly allows new examples. The ban on new rebuttal and the encouragement of new weighing and observations come from established WSDC practice and the Manual.

### When 3O brings late but valid rebuttal

The Proposition reply can't simply rebut it with something new, but it can:

- **Evaluate it**: show the response doesn't land (e.g. "they never asked *compared to what?*").
- **Outweigh it**: even if it's true, it matters less than the reasons Proposition already gave.
- **Reframe existing material**: show that earlier Proposition analysis already answers it. Use this sparingly, only for significant late rebuttal.

If 3O makes a genuinely **new argument**, the reply speaker can't rebut it, but can point out that it was new and shouldn't count.

## Notes for judges

- **Don't over-credit.** A new mechanism, harm or response in a reply must be discounted, however persuasive it sounds in a close round.
- **Don't under-value.** Sharp new commentary (an unaddressed assumption, a contradiction, a useful way to compare clashes) is allowed. Dismissing it as "new" is a mistake.
- **Score replies separately** from the same speaker's substantive speech, out of 50, within the range 30–40.
$m$,
  $q$[
 {
  "type": "mcq",
  "question": "3O builds a brand-new mechanism and impact (\"streaming entrenches class inequality\") and weighs it against Proposition's argument. How should you treat it?",
  "options": [
   "Credit it fully. It's framed as weighing, so it counts as rebuttal.",
   "Treat it as a new argument and don't credit it, unless it was announced in the case division at 1O",
   "Credit it, but lower 3O's style score",
   "Credit it only if Proposition doesn't object at reply"
  ],
  "answer": 1,
  "explanation": "A new standalone argument (new mechanism + new impact) is still a new argument even when framed as weighing. Unless the first speaker announced that third would present that part of the case (Rules, Schedule 1 §9.3), it shouldn't be credited. Calling it weighing doesn't make it rebuttal."
 },
 {
  "type": "mcq",
  "question": "Which of these is expected of a third speaker?",
  "options": [
   "Repeating their team's case so the judge remembers it",
   "New rebuttal, including first responses to earlier claims",
   "A new independent argument to finish strong",
   "Responding to every line the other team said, in order"
  ],
  "answer": 1,
  "explanation": "Third speakers are expected to bring new rebuttal (direct responses or weighing) and to develop existing rebuttal. A third speech without new rebuttal isn't doing its job. Going line by line isn't required; good thirds organise the debate into 2–4 clashes."
 },
 {
  "type": "mcq",
  "question": "1O and 2O never responded to 1P's main argument. 3O responds to it thoroughly and well. What follows?",
  "options": [
   "The response is impermissible because it is too late",
   "The response is allowed and may win that clash, but the earlier neglect still counts against 1O and 2O's scores, and other Prop material may stand",
   "The response is allowed and fully cancels the earlier neglect",
   "Proposition automatically wins the clash because the response was late"
  ],
  "answer": 1,
  "explanation": "Late engagement is permitted and can be decisive, but it doesn't erase earlier neglect. Ask whether 3O fully neutralises the argument and whether Proposition still holds uncontested ground elsewhere. Then reflect the delayed response in the first and second speakers' marks."
 },
 {
  "type": "mcq",
  "question": "Which of these may a reply speaker do?",
  "options": [
   "Offer a new mechanism showing the other side's harm is already solved",
   "Introduce a new benefit to a different actor",
   "Introduce a new way of weighing the existing clashes",
   "Directly rebut a new argument made at 3O"
  ],
  "answer": 2,
  "explanation": "Replies can bring new weighing, new observations about the debate (dropped arguments, contradictions, unmet burdens) and new examples for existing arguments. New mechanisms, new benefits and new rebuttal are not allowed. A reply speaker facing a new 3O argument should point out that it was new and shouldn't count."
 },
 {
  "type": "mcq",
  "question": "A reply speaker says, \"At no point did Opposition respond to our claim that private prisons lobby for harsher sentences, so that harm stands.\" What is this?",
  "options": [
   "New rebuttal, not allowed",
   "A new argument, not allowed",
   "A new observation about the debate, allowed and encouraged",
   "A new example, allowed only if one was given earlier"
  ],
  "answer": 2,
  "explanation": "Pointing out a dropped argument is an observation about how the debate went. It adds no new reasoning, so it's exactly the kind of evaluation reply speeches should offer. Don't dismiss sharp commentary like this as \"new\"."
 },
 {
  "type": "open",
  "question": "3O introduces new but valid rebuttal to a 1P argument for the first time. Briefly describe two ways the Proposition reply could deal with it without breaking the rules.",
  "model_answer": "(1) Evaluate it: use observations to show the late response doesn't land, e.g. it never answers the comparison ('compared to what?'). (2) Outweigh it: even if the response is true, it's less important than the reasons Proposition already gave for winning. (3) Reframe existing material: show that analysis Proposition already gave implicitly answers the new response. The reply cannot offer brand-new rebuttal of its own."
 }
]$q$::jsonb,
  2, true)
on conflict (slug) do nothing;

