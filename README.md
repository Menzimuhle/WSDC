# WSDC Judge Training

A free training site for WSDC judges:

- **Open training, no email link needed**: share the site link and judges start straight away. The first time, they enter their name, email and nation, and get a guest account in the background. Their progress is saved, they can pick up where they left off, and the CA team can see who has completed what.
- **Training modules**: written lessons with optional embedded videos, each ending in a practice quiz that shows the expected answer and the reasoning.
- **Final placement test**: judges request a sign-in link on the Final test page with their registered email. The test has multiple choice, judging a recorded debate (call + speaker scores), and written answers. One attempt each, timed, autosaved, and only open to approved emails. Their training record is merged into the same account automatically.
- **CA dashboard**: results table with CSV export, anonymous marking of written answers against a rubric, training progress, a question editor, the approved-judge list and test settings (open/close times, time limit, releasing results).

Runs free on **GitHub Pages** (the website) and **Supabase** (logins and database).

---

## How the final test stays secure

The site's code is public on GitHub, so **no questions, answer keys or rubrics live in the code**. They're stored only in Supabase and protected by database rules (`supabase/schema.sql`):

- Judges can't read the question table. They receive questions through a database function that strips out answer keys and rubrics.
- Marking happens in the database, not the browser.
- Each judge gets one attempt. The deadline is enforced by the database, not just the on-screen timer. Saving stops 30 seconds after the deadline.
- Only emails on the approved list can start the test, and only between the open and close times. The check uses the email proven by the emailed link, never the email a guest typed in, so nobody can take the test by typing in another judge's email.
- Scores stay hidden from judges until a CA ticks **Results released**.
- Judges can only edit their own name and nation, never their role.

---

## One-time setup (about 30 minutes)

### 1. Supabase
1. Create a free project at [supabase.com](https://supabase.com).
2. Go to **SQL Editor → New query**, paste the contents of `supabase/schema.sql`, and click **Run**.
3. Go to **Authentication → Sign In / Providers** and turn on **Allow anonymous sign-ins** (this powers the no-email guest training accounts). Leave **Email** enabled for the final test.
   - Supabase limits how many guest accounts can be created per hour from one internet connection. If you run a live training session where many judges share one Wi-Fi network, raise the limit under **Authentication → Rate Limits** beforehand.
   - Optional: switch on CAPTCHA protection (Authentication → Attack Protection) to stop bots creating guest accounts.
4. Go to **Authentication → URL Configuration**:
   - **Site URL**: `https://YOUR-GITHUB-USERNAME.github.io/REPO-NAME/`
   - **Redirect URLs**: add `https://YOUR-GITHUB-USERNAME.github.io/REPO-NAME/**` (and `http://localhost:4321/**` for local testing).
5. **Email sending.** Supabase's built-in email only sends a handful of sign-in emails per hour, which is fine for testing but not for a cohort of judges. Before inviting judges, go to **Authentication → Emails → SMTP settings** and connect a free email service (e.g. Resend or Brevo).
6. Go to **Project Settings → API** and copy the **Project URL** and the **anon / publishable key**. Both are safe to make public.

### 2. GitHub
1. Push this folder to a new repository.
2. **Settings → Pages → Source: GitHub Actions**.
3. **Settings → Secrets and variables → Actions → Variables** tab, then add:
   - `PUBLIC_SUPABASE_URL`
   - `PUBLIC_SUPABASE_ANON_KEY`
4. Push to `main` (or run the workflow manually). The site appears at `https://YOUR-GITHUB-USERNAME.github.io/REPO-NAME/`.

### 3. Make yourself an admin
Sign in on the site once, then in Supabase **SQL Editor** run:
```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```
Reload the site and an **Admin** link appears. Repeat for each CA.

---

## Day-to-day use

### Adding or editing a module
Modules are Markdown files in `src/content/modules/`. Copy an existing one and change the top section:

```yaml
---
title: Scoring and margins
order: 3                      # position in the list
minutes: 20                   # optional
summary: One line shown in the module list.
video: https://youtu.be/...   # optional, unlisted YouTube links work
draft: true                   # hides it until you're ready
quiz:
  - type: mcq
    question: ...
    options: [ "...", "...", "..." ]
    answer: 1                 # 0 = first option
    explanation: Shown after answering. Explain why, and cite the Manual/Rules.
  - type: open
    question: A practice written question
    model_answer: Shown when the judge clicks "Show model answer".
---
Lesson text in Markdown...
```

You can edit files directly on github.com. The site rebuilds automatically in about a minute.

> Practice quizzes are in the public code, so judges can see those answers. That's fine for practice. Put anything used for placement in the final test instead.

### How judges move between devices
Training progress is tied to the browser they started on. To continue elsewhere, judges either:
- click **Send confirmation link** on their details page (top-right name), after which they can sign in anywhere with that email; or
- use **Sign in with email** (footer) on the new device with the same email they typed in, and their progress is copied across automatically.

The CA **Training progress** tab marks each judge as **Guest** (email typed in, unconfirmed) or **Verified** (signed in through an emailed link).

### Running the final test
1. **Admin → Final test questions**: add questions. Multiple choice, debate call, speaker scores (with the CA panel's reference scores and a tolerance) and written answers (with a marking rubric). For the debate, paste an **unlisted** YouTube link in "Video or link".
2. **Admin → Approved judges**: paste the registered judges' emails. The status column shows who is already training and who has signed in.
3. **Admin → Test settings**: set the open/close times and the time limit.
4. Email judges the site link with "go to Final test and enter your registered email". During the test: **Results** shows who has started and submitted.
5. After the test closes: click **Close timed-out attempts** (submits anyone who ran out of time without pressing Submit), then mark written answers under **Marking**. Names are hidden by default, so you mark anonymously.
6. **Export CSV** for allocations. Tick **Results released** if judges should see their own scores and marker comments.

**How automatic marking works**
- Multiple choice and debate call: full marks for the correct answer.
- Speaker scores: marks are split evenly across speakers, and a judge gets credit for each score within ± tolerance of the reference. For example, with 4 marks, 8 speakers and ±1, getting 6 within range earns 3 marks.
- If you fix an answer key after people have submitted, click **Re-mark automatic questions**.

---

## Local development
```bash
npm install
cp .env.example .env   # fill in your Supabase URL and key (or leave blank for preview mode)
npm run dev            # http://localhost:4321
```

## Free-tier notes
- Supabase pauses free projects after about a week with no activity. Open the site or dashboard occasionally, especially before a test window. Restoring a paused project takes a few minutes from the Supabase dashboard.
- Host videos on YouTube (unlisted), not on GitHub or Supabase.

## Structure
```
src/content/modules/   lessons + practice quizzes (Markdown)
src/pages/             home, modules, login, account, final test, admin
src/lib/supabase.js    Supabase client + helpers
supabase/schema.sql    database tables, security rules and marking functions
supabase/final_questions.example.sql   sample test questions for trying it out
.github/workflows/     automatic deploy to GitHub Pages
```
