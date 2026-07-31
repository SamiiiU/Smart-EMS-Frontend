# Smart EMS

Multi-tenant SaaS for educational institutions (schools, colleges,
academies, madrassas) in Pakistan. Backend (Spring Boot / Java 21 /
PostgreSQL) is a separate, already-built repository owned by Ali. This
repository holds the Flutter client.

## Layout

- `frontend/` — the entire Flutter project (Android + Web). All Flutter
  commands run from inside this directory.
- `CLAUDE.md`, `DECISIONS.md`, `PROJECT_STATUS.md`, `BACKEND_CONTRACT.md`,
  `HANDOFF.md` — root-level context files kept up to date as tasks proceed.
- `.claude/skills/` — project skills (design system, task gate, context
  sync, backend contract), seeded and updated alongside the tasks below.
- `backend/` — a local clone of Ali's separate backend repository (its
  own `.git`), kept only to run the API for development. Never edited,
  never committed here — see the setup step below.

## First-time setup after cloning

Run this once per clone so the `backend/` safety guard is active:

```
git config core.hooksPath .githooks
```

This points git at `.githooks/pre-commit`, which refuses any commit that
has a path under `backend/` staged (`.gitignore` alone isn't a hard
guarantee — `git add -f` bypasses it). `core.hooksPath` is a local git
config, not a tracked file, so every clone must run this once.
