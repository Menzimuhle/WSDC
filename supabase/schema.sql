-- =====================================================================
-- WSDC Judge Training – database schema
-- Run this once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
--
-- Security model
--  * Judges never read the final-quiz tables directly. They go through the
--    SECURITY DEFINER functions below, which never return answer keys or
--    scores before the CAs release results.
--  * Answer keys live only in this database, never in the website code
--    (the GitHub repo is public).
--  * Admins (profiles.role = 'admin') can read and mark everything.
--
-- Two kinds of account
--  * Guests: anyone doing the training. They fill in name/email/nation and get
--    an anonymous Supabase account in the background, with no email sent.
--    Their email is self-reported (`email`), so it is never trusted for the test.
--  * Verified: signed in through an emailed link. `verified_email` is set by
--    the trigger below from Supabase Auth and cannot be edited by the user.
--    Only verified emails on the allowlist can sit the final test.
-- =====================================================================

-- ---------- Profiles -------------------------------------------------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  email          text,                 -- contact email (self-reported by guests)
  verified_email text,                 -- set only from Supabase Auth
  full_name      text,
  nation         text,
  is_guest       boolean not null default false,
  merged_into    uuid references public.profiles(id) on delete set null,
  role           text not null default 'judge' check (role in ('judge', 'admin')),
  created_at     timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, verified_email, is_guest)
  values (new.id, lower(new.email),
          case when new.email_confirmed_at is not null then lower(new.email) end,
          coalesce(new.is_anonymous, false))
  on conflict (id) do nothing;
  return new;
end $$;

-- Keeps verified_email / is_guest in sync, e.g. when an emailed link is clicked
-- or a guest confirms their email to use another device.
create or replace function public.handle_user_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set verified_email = case when new.email_confirmed_at is not null then lower(new.email) else verified_email end,
         email          = coalesce(email, lower(new.email)),
         is_guest       = coalesce(new.is_anonymous, false)
   where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update of email, email_confirmed_at, is_anonymous on auth.users
  for each row execute function public.handle_user_update();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- Training progress ----------------------------------------
create table if not exists public.module_progress (
  user_id        uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  module_slug    text not null,
  practice_score int,
  practice_total int,
  completed_at   timestamptz,
  updated_at     timestamptz not null default now(),
  primary key (user_id, module_slug)
);

-- ---------- Final quiz -----------------------------------------------
-- Who may sit the final quiz (emails registered for the tournament).
create table if not exists public.final_allowlist (
  email    text primary key check (email = lower(email)),
  note     text,
  added_at timestamptz not null default now()
);

-- Single row of settings.
create table if not exists public.final_settings (
  id                 int primary key default 1 check (id = 1),
  title              text not null default 'Final Judge Test',
  instructions       text,
  opens_at           timestamptz,
  closes_at          timestamptz,
  time_limit_minutes int not null default 90 check (time_limit_minutes > 0),
  results_released   boolean not null default false
);
insert into public.final_settings (id) values (1) on conflict do nothing;

-- Questions. kind:
--   mcq     options = ["text", ...]                     answer_key = {"correct": <index>}
--   call    options = ["Proposition","Opposition"]      answer_key = {"correct": "Opposition"}
--   scores  options = [{"label":"1st Prop","min":60,"max":80}, ...]
--                                                       answer_key = {"reference":[72, ...], "tolerance": 1.5}
--   written options = null                              marked by CAs using `rubric`
-- section groups questions on the test: mcq → debate → written.
create table if not exists public.final_questions (
  id         bigint generated always as identity primary key,
  section    text not null check (section in ('mcq', 'debate', 'written')),
  kind       text not null check (kind in ('mcq', 'call', 'scores', 'written')),
  position   int  not null default 0,
  prompt     text not null,
  media_url  text,
  options    jsonb,
  answer_key jsonb,
  points     numeric not null default 1 check (points >= 0),
  rubric     text,
  active     boolean not null default true
);

create table if not exists public.final_attempts (
  id             bigint generated always as identity primary key,
  user_id        uuid not null unique references public.profiles(id) on delete cascade,
  started_at     timestamptz not null default now(),
  deadline       timestamptz not null,
  submitted_at   timestamptz,
  question_order bigint[] not null
);

create table if not exists public.final_answers (
  attempt_id     bigint not null references public.final_attempts(id) on delete cascade,
  question_id    bigint not null references public.final_questions(id) on delete cascade,
  answer         jsonb,
  saved_at       timestamptz not null default now(),
  auto_points    numeric,
  manual_points  numeric,
  marker_comment text,
  marked_by      uuid references public.profiles(id),
  marked_at      timestamptz,
  primary key (attempt_id, question_id)
);

-- ---------- Row Level Security ---------------------------------------
alter table public.profiles        enable row level security;
alter table public.module_progress enable row level security;
alter table public.final_allowlist enable row level security;
alter table public.final_settings  enable row level security;
alter table public.final_questions enable row level security;
alter table public.final_attempts  enable row level security;
alter table public.final_answers   enable row level security;

revoke all on public.profiles, public.module_progress, public.final_allowlist,
  public.final_settings, public.final_questions, public.final_attempts,
  public.final_answers from anon;

-- Judges may edit only their name, nation and contact email: never their
-- role or verified email.
revoke update on public.profiles from authenticated;
grant  update (full_name, nation, email) on public.profiles to authenticated;

drop policy if exists "profiles: read own or admin" on public.profiles;
create policy "profiles: read own or admin" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "progress: own rows" on public.module_progress;
create policy "progress: own rows" on public.module_progress
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "progress: admin read" on public.module_progress;
create policy "progress: admin read" on public.module_progress
  for select to authenticated using (public.is_admin());

drop policy if exists "allowlist: admin" on public.final_allowlist;
create policy "allowlist: admin" on public.final_allowlist
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "settings: admin" on public.final_settings;
create policy "settings: admin" on public.final_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "questions: admin" on public.final_questions;
create policy "questions: admin" on public.final_questions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "attempts: admin" on public.final_attempts;
create policy "attempts: admin" on public.final_attempts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "answers: admin" on public.final_answers;
create policy "answers: admin" on public.final_answers
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- Marking --------------------------------------------------
create or replace function public._auto_points(q public.final_questions, a jsonb)
returns numeric language plpgsql immutable as $$
declare
  ref jsonb; tol numeric; n int; hits int := 0; i int; v numeric;
begin
  if a is null then
    return case when q.kind = 'written' then null else 0 end;
  end if;
  if q.kind = 'mcq' then
    return case when (a->>'choice')::int = (q.answer_key->>'correct')::int then q.points else 0 end;
  elsif q.kind = 'call' then
    return case when a->>'choice' = q.answer_key->>'correct' then q.points else 0 end;
  elsif q.kind = 'scores' then
    ref := q.answer_key->'reference';
    tol := coalesce((q.answer_key->>'tolerance')::numeric, 1);
    n   := jsonb_array_length(ref);
    if n = 0 or jsonb_typeof(a->'scores') <> 'array' then return 0; end if;
    for i in 0 .. n - 1 loop
      begin
        v := (a->'scores'->>i)::numeric;
        if v is not null and abs(v - (ref->>i)::numeric) <= tol then hits := hits + 1; end if;
      exception when others then null;
      end;
    end loop;
    return round(q.points * hits / n, 2);
  end if;
  return null; -- written: marked by a CA
end $$;

create or replace function public._grade_attempt(p_attempt bigint)
returns void language sql security definer set search_path = public as $$
  update public.final_answers fa
     set auto_points = public._auto_points(q, fa.answer)
    from public.final_questions q
   where q.id = fa.question_id and fa.attempt_id = p_attempt;
$$;

-- ---------- Judge-facing functions -----------------------------------
create or replace function public.final_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.final_settings; a public.final_attempts; me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'Not signed in'; end if;
  select * into s from public.final_settings where id = 1;
  select * into a from public.final_attempts where user_id = me.id;
  return jsonb_build_object(
    'title', s.title, 'instructions', s.instructions,
    'opens_at', s.opens_at, 'closes_at', s.closes_at,
    'time_limit_minutes', s.time_limit_minutes,
    'results_released', s.results_released,
    'now', now(),
    'eligible', exists (select 1 from public.final_allowlist where email = me.verified_email),
    'verified', me.verified_email is not null,
    'is_open', s.opens_at is not null and now() >= s.opens_at and (s.closes_at is null or now() < s.closes_at),
    'attempt', case when a.id is null then null else jsonb_build_object(
        'started_at', a.started_at, 'deadline', a.deadline, 'submitted_at', a.submitted_at) end);
end $$;

create or replace function public.start_final()
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.final_settings; a public.final_attempts; me public.profiles;
        v_deadline timestamptz; v_order bigint[];
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then raise exception 'Not signed in'; end if;
  select * into s from public.final_settings where id = 1;
  select * into a from public.final_attempts where user_id = me.id;

  if a.id is null then
    if not exists (select 1 from public.final_allowlist where email = me.verified_email) then
      raise exception 'You are not on the list for the final test. Contact the CA team.';
    end if;
    if s.opens_at is null or now() < s.opens_at then raise exception 'The final test is not open yet.'; end if;
    if s.closes_at is not null and now() >= s.closes_at then raise exception 'The final test has closed.'; end if;

    v_deadline := now() + make_interval(mins => s.time_limit_minutes);
    if s.closes_at is not null and s.closes_at < v_deadline then v_deadline := s.closes_at; end if;

    select array_agg(id order by
             case section when 'mcq' then 1 when 'debate' then 2 else 3 end,
             case when section = 'mcq' then random() else 0 end,
             position, id)
      into v_order from public.final_questions where active;
    if v_order is null then raise exception 'No questions have been set up yet.'; end if;

    insert into public.final_attempts (user_id, deadline, question_order)
    values (me.id, v_deadline, v_order) returning * into a;
  elsif a.submitted_at is not null then
    raise exception 'You have already submitted the final test.';
  elsif now() > a.deadline then
    raise exception 'Your time for the final test has run out.';
  end if;

  return jsonb_build_object(
    'deadline', a.deadline,
    'now', now(),
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'id', q.id, 'section', q.section, 'kind', q.kind, 'prompt', q.prompt,
               'media_url', q.media_url, 'options', q.options, 'points', q.points)
             order by o.ord)
        from unnest(a.question_order) with ordinality o(qid, ord)
        join public.final_questions q on q.id = o.qid),
    'answers', coalesce((
      select jsonb_object_agg(question_id::text, answer)
        from public.final_answers where attempt_id = a.id), '{}'::jsonb));
end $$;

create or replace function public.save_final_answer(p_question_id bigint, p_answer jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare a public.final_attempts;
begin
  select * into a from public.final_attempts where user_id = auth.uid();
  if a.id is null then raise exception 'You have not started the final test.'; end if;
  if a.submitted_at is not null then raise exception 'Already submitted.'; end if;
  -- 30 seconds of grace for network delay
  if now() > a.deadline + interval '30 seconds' then raise exception 'Time is up.'; end if;
  if not (p_question_id = any (a.question_order)) then raise exception 'Unknown question.'; end if;
  if pg_column_size(p_answer) > 40000 then raise exception 'Answer is too long.'; end if;

  insert into public.final_answers (attempt_id, question_id, answer, saved_at)
  values (a.id, p_question_id, p_answer, now())
  on conflict (attempt_id, question_id)
  do update set answer = excluded.answer, saved_at = excluded.saved_at;
end $$;

create or replace function public.submit_final()
returns void language plpgsql security definer set search_path = public as $$
declare a public.final_attempts;
begin
  select * into a from public.final_attempts where user_id = auth.uid();
  if a.id is null then raise exception 'You have not started the final test.'; end if;
  if a.submitted_at is not null then return; end if;
  -- make sure every question has a row, so unanswered questions score 0
  insert into public.final_answers (attempt_id, question_id, answer)
  select a.id, qid, null from unnest(a.question_order) qid
  on conflict do nothing;
  update public.final_attempts set submitted_at = least(now(), deadline + interval '30 seconds') where id = a.id;
  perform public._grade_attempt(a.id);
end $$;

create or replace function public.my_final_result()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.final_attempts;
begin
  if not (select results_released from public.final_settings where id = 1) then return null; end if;
  select * into a from public.final_attempts where user_id = auth.uid();
  if a.id is null or a.submitted_at is null then return null; end if;
  return (
    with per as (
      select q.section, q.position, q.prompt, fa.marker_comment,
             coalesce(fa.manual_points, fa.auto_points, 0) pts, q.points mx
        from public.final_answers fa join public.final_questions q on q.id = fa.question_id
       where fa.attempt_id = a.id),
    sec as (select section, sum(pts) score, sum(mx) mx from per group by section)
    select jsonb_build_object(
      'total',    (select sum(pts) from per),
      'max',      (select sum(mx) from per),
      'sections', (select jsonb_object_agg(section, jsonb_build_object('score', score, 'max', mx)) from sec),
      'feedback', coalesce((select jsonb_agg(jsonb_build_object('prompt', prompt, 'comment', marker_comment) order by section, position)
                              from per where marker_comment is not null and marker_comment <> ''), '[]'::jsonb))
  );
end $$;

-- When a judge signs in with an emailed link (e.g. for the final test) on a
-- different device from where they trained as a guest, pull in the training
-- progress from guest accounts that gave the same email. The emailed link
-- proves they own that email.
create or replace function public.merge_guest_training()
returns int language plpgsql security definer set search_path = public as $$
declare me public.profiles; g record; n int := 0;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.verified_email is null then return 0; end if;
  for g in select * from public.profiles
            where is_guest and merged_into is null and id <> me.id and lower(email) = me.verified_email loop
    insert into public.module_progress (user_id, module_slug, practice_score, practice_total, completed_at, updated_at)
    select me.id, module_slug, practice_score, practice_total, completed_at, updated_at
      from public.module_progress where user_id = g.id
    on conflict (user_id, module_slug) do update set
      practice_score = greatest(module_progress.practice_score, excluded.practice_score),
      practice_total = coalesce(module_progress.practice_total, excluded.practice_total),
      completed_at   = least(coalesce(module_progress.completed_at, excluded.completed_at), coalesce(excluded.completed_at, module_progress.completed_at)),
      updated_at     = greatest(module_progress.updated_at, excluded.updated_at);
    update public.profiles set
      full_name = coalesce(full_name, g.full_name),
      nation    = coalesce(nation, g.nation)
     where id = me.id;
    update public.profiles set merged_into = me.id where id = g.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- Admin functions ------------------------------------------
create or replace function public.admin_close_expired()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  for r in select * from public.final_attempts where submitted_at is null and now() > deadline + interval '30 seconds' loop
    insert into public.final_answers (attempt_id, question_id, answer)
    select r.id, qid, null from unnest(r.question_order) qid on conflict do nothing;
    update public.final_attempts set submitted_at = r.deadline where id = r.id;
    perform public._grade_attempt(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.admin_regrade_all()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  for r in select id from public.final_attempts where submitted_at is not null loop
    perform public._grade_attempt(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.admin_mark_answer(p_attempt bigint, p_question bigint, p_points numeric, p_comment text)
returns void language plpgsql security definer set search_path = public as $$
declare maxp numeric;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select points into maxp from public.final_questions where id = p_question;
  if p_points is not null and (p_points < 0 or p_points > maxp) then
    raise exception 'Mark must be between 0 and %', maxp;
  end if;
  update public.final_answers
     set manual_points = p_points, marker_comment = p_comment,
         marked_by = auth.uid(), marked_at = now()
   where attempt_id = p_attempt and question_id = p_question;
  if not found then raise exception 'Answer not found'; end if;
end $$;

create or replace function public.admin_results()
returns table (
  user_id uuid, full_name text, email text, nation text,
  started_at timestamptz, submitted_at timestamptz,
  mcq numeric, mcq_max numeric, debate numeric, debate_max numeric,
  written numeric, written_max numeric,
  to_mark int, total numeric, total_max numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
  select p.id, p.full_name, coalesce(p.verified_email, p.email), p.nation, a.started_at, a.submitted_at,
    sum(coalesce(fa.manual_points, fa.auto_points, 0)) filter (where q.section = 'mcq'),
    sum(q.points) filter (where q.section = 'mcq'),
    sum(coalesce(fa.manual_points, fa.auto_points, 0)) filter (where q.section = 'debate'),
    sum(q.points) filter (where q.section = 'debate'),
    sum(coalesce(fa.manual_points, fa.auto_points, 0)) filter (where q.section = 'written'),
    sum(q.points) filter (where q.section = 'written'),
    (count(*) filter (where q.kind = 'written' and fa.manual_points is null))::int,
    sum(coalesce(fa.manual_points, fa.auto_points, 0)),
    sum(q.points)
  from public.final_attempts a
  join public.profiles p on p.id = a.user_id
  left join public.final_answers fa on fa.attempt_id = a.id
  left join public.final_questions q on q.id = fa.question_id
  group by p.id, p.full_name, p.verified_email, p.email, p.nation, a.started_at, a.submitted_at
  order by sum(coalesce(fa.manual_points, fa.auto_points, 0)) desc nulls last;
end $$;

-- Only signed-in users may call the functions (each one checks further).
revoke execute on function public._auto_points(public.final_questions, jsonb) from public, anon, authenticated;
revoke execute on function public._grade_attempt(bigint) from public, anon, authenticated;
revoke execute on function public.final_status(), public.start_final(), public.save_final_answer(bigint, jsonb),
  public.submit_final(), public.my_final_result(), public.merge_guest_training(), public.admin_close_expired(), public.admin_regrade_all(),
  public.admin_mark_answer(bigint, bigint, numeric, text), public.admin_results() from public, anon;
grant execute on function public.final_status(), public.start_final(), public.save_final_answer(bigint, jsonb),
  public.submit_final(), public.my_final_result(), public.merge_guest_training(), public.admin_close_expired(), public.admin_regrade_all(),
  public.admin_mark_answer(bigint, bigint, numeric, text), public.admin_results(), public.is_admin() to authenticated;
