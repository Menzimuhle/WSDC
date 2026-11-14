# WSDC Judge Training

A free, open-access training platform for World Schools Debating Championships (WSDC) adjudicators. Judges work through self-paced modules and practice quizzes, then sit a timed placement test that the CA team marks and uses for tournament allocations.

**Live site:** https://menzimuhle.github.io/WSDC/

---

## Features

**For judges**
- Self-paced training modules with lesson text, images and embedded YouTube video
- Practice quizzes with instant feedback, explanations and model answers
- Open access, with no account or email link needed. Progress is saved against a lightweight guest identity and resumes automatically
- A timed final test with three sections: multiple choice, judging a recorded debate (call + speaker scores), and written answers
- Answers autosave during the test, and the server keeps the deadline even if the page is closed

**For the CA team (admin dashboard)**
- **Module editor:** Markdown editor with toolbar, live preview, image upload and a practice-quiz builder; publish/draft and reordering
- **Final test editor:** per-type question forms (MCQ, debate call, speaker scores with reference + tolerance, written with rubric)
- **Marking:** anonymised marking of written answers against a rubric, with optional feedback to the judge
- **Results:** ranked table with section scores and CSV export
- **Training progress:** completion and practice scores per judge, with CSV export
- **Access and settings:** approved-judge allowlist, test window, time limit, and a switch to release results

---

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | [Astro](https://astro.build) (static output) with vanilla TypeScript/JavaScript |
| Hosting | GitHub Pages, deployed by GitHub Actions |
| Backend | [Supabase](https://supabase.com): Postgres, Auth, Storage |
| Auth | Supabase anonymous sign-in (training) + email magic link (final test, admins) |
| Content | Markdown via [marked](https://marked.js.org), sanitised with [DOMPurify](https://github.com/cure53/DOMPurify) |
| Editor | [EasyMDE](https://github.com/Ionaru/easy-markdown-editor) + Font Awesome 4 (bundled) |

There's no application server. The static site talks directly to Supabase, and all access control is enforced in Postgres through Row Level Security and `SECURITY DEFINER` functions.

---

## Architecture

```
┌─────────────────────────┐        HTTPS (supabase-js)        ┌──────────────────────────────┐
│  Static site            │ ────────────────────────────────▶ │  Supabase                    │
│  (GitHub Pages)         │                                   │                              │
│                         │   REST: training_modules,         │  Auth   anonymous + OTP      │
│  Astro pages +          │         module_progress,          │  Postgres                    │
│  client-side scripts    │         profiles (RLS)            │    tables + RLS policies     │
│                         │   RPC:  start_final,              │    SECURITY DEFINER RPCs     │
│                         │         save_final_answer, …      │  Storage  training-media     │
└─────────────────────────┘                                   └──────────────────────────────┘
```

All pages are pre-rendered shells. Data such as modules, progress and test state loads in the browser after the page opens, which keeps the site deployable to any static host and means content edits go live without a rebuild.

### Identity model

| Account | Created by | Email | Used for |
|---|---|---|---|
| **Guest** | `signInAnonymously()` when a judge first submits the details form | Self-reported (`profiles.email`), untrusted | Training progress |
| **Verified** | Email magic link | `profiles.verified_email`, set only by an `auth.users` trigger | Final test, admin |

When a judge later verifies an email, `merge_guest_training()` copies progress from guest profiles that reported the same address into the verified account. A guest can also upgrade in place via `auth.updateUser({ email })`.

### Final-test security

The repository is public, so **no answer keys or rubrics ever reach the client**:

- `final_questions`, `final_attempts` and `final_answers` are readable only by admins (RLS).
- Judges interact solely through RPCs: `start_final()` returns questions with keys and rubrics stripped; `save_final_answer()` refuses writes after `deadline + 30s`; `submit_final()` auto-marks on the server.
- Eligibility is checked against `verified_email` ∩ `final_allowlist`, never the self-reported email.
- `my_final_result()` returns nothing until `final_settings.results_released` is true.
- Column-level grants stop users from editing `role` or `verified_email` on their own profile.

---

## Project structure

```
.
├── .github/workflows/deploy.yml   # Build + deploy to GitHub Pages on push to main
├── docs/SETUP.md                  # Step-by-step setup and admin guide
├── public/                        # Static assets (favicon)
├── src/
│   ├── components/
│   │   └── TraineeGate.astro      # First-visit details form; creates the guest session
│   ├── layouts/
│   │   └── Base.astro             # Shell: header, nav, auth state, footer
│   ├── lib/
│   │   ├── supabase.js            # Client, path helpers, escaping, toasts, CSV export
│   │   ├── progress.js            # Guest identity + module progress (DB, localStorage fallback)
│   │   ├── modules.js             # Fetch modules, Markdown → sanitised HTML, video embeds
│   │   ├── quiz.js                # Practice-quiz renderer
│   │   └── module-editor.js       # Admin → Modules editor and quiz builder
│   ├── pages/
│   │   ├── index.astro            # Home
│   │   ├── modules/index.astro    # Module list + progress
│   │   ├── module.astro           # Single module (/module/?m=<slug>)
│   │   ├── final.astro            # Final test: sign-in, runner, results
│   │   ├── admin.astro            # CA dashboard
│   │   ├── account.astro          # Profile + "continue on another device"
│   │   └── login.astro            # Email sign-in
│   └── styles/global.css          # Design tokens (light/dark) and components
├── supabase/
│   ├── schema.sql                 # Core tables, RLS, triggers, final-test RPCs
│   ├── modules.sql                # training_modules, storage bucket, starter content
│   └── final_questions.example.sql
├── astro.config.mjs
└── package.json
```

---

## Data model

| Table | Purpose | Access |
|---|---|---|
| `profiles` | One row per auth user: name, nation, role, guest/verified emails | Own row; admins read all |
| `training_modules` | Module content (Markdown), practice quiz (JSONB), order, published flag | Public reads published; admins write |
| `module_progress` | Per-user, per-module completion and best practice score | Own rows; admins read |
| `final_settings` | Single row: test window, time limit, results released | Admins |
| `final_allowlist` | Emails approved to sit the test | Admins |
| `final_questions` | Questions, answer keys, rubrics | Admins only |
| `final_attempts` | One attempt per user: deadline, question order | Admins (judges via RPC) |
| `final_answers` | Answers, auto marks, manual marks, marker comments | Admins (judges via RPC) |

**Question kinds** (`final_questions.kind`):

| Kind | `options` | `answer_key` | Marking |
|---|---|---|---|
| `mcq` | `["…", "…"]` | `{ "correct": <index> }` | Full marks if correct |
| `call` | `["Proposition", "Opposition"]` | `{ "correct": "Opposition" }` | Full marks if correct |
| `scores` | `[{ label, side, min, max }, …]` | `{ "reference": [...], "tolerance": 1.5 }` | Pro-rata per speaker within ± tolerance |
| `written` | – | – | Manual, by a CA using `rubric` |

**RPCs:** `final_status`, `start_final`, `save_final_answer`, `submit_final`, `my_final_result`, `merge_guest_training`, `is_admin`, and the admin-only `admin_results`, `admin_mark_answer`, `admin_close_expired`, `admin_regrade_all`.

---

## Getting started

### Prerequisites
- Node.js 22+
- A Supabase project with `supabase/schema.sql` and then `supabase/modules.sql` run in the SQL editor
- Anonymous sign-ins enabled in Supabase Auth

### Local development

```bash
git clone https://github.com/Menzimuhle/WSDC.git
cd WSDC
npm install
cp .env.example .env    # add your Supabase URL and publishable key
npm run dev             # http://localhost:4321
```

Without a `.env`, the site runs in **preview mode**: pages render, but anything that needs Supabase is switched off.

### Environment variables

| Variable | Description |
|---|---|
| `PUBLIC_SUPABASE_URL` | Project URL, e.g. `https://<project-id>.supabase.co` |
| `PUBLIC_SUPABASE_ANON_KEY` | Publishable (anon) key, safe to expose because security comes from RLS |
| `SITE_URL` | *(build only)* Canonical origin; set by CI |
| `BASE_PATH` | *(build only)* Sub-path for GitHub Pages, e.g. `/WSDC`; set by CI |

Never use the Supabase **secret / service-role** key in this project.

### Scripts

| Command | Description |
|---|---|
| `npm run dev` | Start the dev server with hot reload |
| `npm run build` | Build the static site into `dist/` |
| `npm run preview` | Serve the production build locally |

---

## Deployment

Pushing to `main` triggers `.github/workflows/deploy.yml`, which builds the site and publishes it to GitHub Pages. The workflow reads `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_ANON_KEY` from **repository variables** (Settings → Secrets and variables → Actions → Variables) and derives `BASE_PATH` from the repository name.

For a custom domain, set `BASE_PATH` to `/` and `SITE_URL` to the domain in the workflow, and add the domain under Settings → Pages.

Database changes are applied by running SQL files in the Supabase SQL editor. Both files are idempotent and safe to re-run.

See **[docs/SETUP.md](docs/SETUP.md)** for the full first-time setup (Supabase auth, email/SMTP, admin accounts) and the day-to-day admin guide.

---

## Content management

Training content lives in the database, not the repository. CAs manage it from **Admin → Modules** on the live site. Lesson bodies are Markdown, and a YouTube URL on its own line renders as an embedded player. Images upload to the public `training-media` storage bucket.

Practice-quiz answers are readable by anyone, by design. Anything used for placement belongs in **Admin → Final test questions**, which is admin-only.

---

## Contributing

1. Create a branch from `main`.
2. Run `npm run build` to make sure the site compiles.
3. If you change the schema, edit the relevant file in `supabase/`, keep it idempotent (`if not exists`, `create or replace`, `drop policy if exists`), and note in your PR that it needs to be re-run.
4. Never commit real final-test questions or answer keys. `.gitignore` excludes `supabase/final_questions*.sql` (except the example).

---

## License

No license has been chosen yet. Add a `LICENSE` file before accepting outside contributions.
