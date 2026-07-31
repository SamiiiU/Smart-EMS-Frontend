# Smart EMS — Flutter frontend facts

## Stack

- Flutter (Android + Web targets), Dart SDK `^3.12.0`.
- State: `flutter_riverpod` / `riverpod_annotation` 2.6.1 (hand-written
  providers — no `riverpod_generator`, see Blocked note below).
- Routing: `go_router` (`StatefulShellRoute.indexedStack` planned for T5).
- HTTP: `dio`. Fonts: `google_fonts`. Local DB: `drift` + `drift_flutter` +
  `sqlite3_flutter_libs` (native), in-memory no-op executor (web) — see
  `lib/core/db/`.
## Dev environment facts

- **Backend**: runs locally in **Docker** at **`http://localhost:8080`**
  (Spring Boot / Java 21 / PostgreSQL — Ali's separate repository).
- **Never read `backend/` source to derive the API's behaviour.** The
  contract is verified against the **running API only** — observed requests
  and responses, never source reading. `backend/` exists solely to run the
  API locally. See `BACKEND_CONTRACT.md`.
- **The dev web port is FIXED at 3000. It is not a preference.** The backend
  CORS allowlist is origin-exact, so any other port is blocked by the
  browser. Not something to remember:
  - `.vscode/launch.json` → Chrome config passes `--web-port=3000`
  - CLI: `flutter run -d chrome --web-port=3000` (also in `frontend/README.md`)
  - Port 3000 is **dev tooling**. It is NOT hardcoded anywhere in `lib/`
    and must not be.
- **CORS works on port 3000. Do NOT use `--disable-web-security`.**
  Verified 2026-07-30 against the running API: the backend allowlists
  `http://localhost:3000` and returns
  `Access-Control-Allow-Origin: http://localhost:3000`. A non-allowlisted
  origin gets `403` with no CORS header, so it is a real allowlist, not a
  wildcard. The flag has been removed from the launch config and must not
  come back — it would hide genuine CORS regressions until deployment.
  Details in `BACKEND_CONTRACT.md`.
  *This corrects the Phase 6 T0 spec, which called for a
  `--disable-web-security` launch configuration. That instruction was wrong.*
- **T7 auth is bearer-token only.** `Access-Control-Allow-Credentials` is
  **absent** from the backend's CORS response (measured), so cookie or
  session auth will NOT work cross-origin. `Authorization` IS an allowed
  header, so a bearer token works. Do not design around the missing
  credentials support — raise it with Ali if T7 turns out to need cookies.

## Folder-structure rule

Feature-first under `lib/features/<name>/{data,domain,presentation}`.
Shared code only in `lib/core/{theme,network,db,router,widgets}`. No other
top-level folders under `lib/`.

## Token rule

No raw colours, spacing, or radii anywhere under `lib/` except
`lib/core/theme/` (T1 owns that folder). Enforced by
`frontend/tool/check_tokens.sh`, wired as a PostToolUse hook on Edit/Write.

## Never do this

- Never invent a colour, spacing value, radius, component, or API
  endpoint. If it's not in the design spec / `BACKEND_CONTRACT.md`, stop
  and ask.
- Never hardcode a raw value outside `lib/core/theme/`.
- Never start a task out of order (T0 → T12, strictly gated).
- Never edit backend code — it is Ali's, in a separate repository.
- Never read from, stage, or touch `backend/` at the repo root. It is a
  local clone of Ali's repository (its own `.git`), kept only to run the
  API for development. Out of scope in every task, not just T0.

## Known blocker (dev tooling, not app code)

`riverpod_generator` cannot currently resolve alongside `drift_dev` in
this project's dependency graph (both need incompatible `analyzer`/
`source_gen` versions). `custom_lint` / `riverpod_lint` were dropped for
the same reason. Riverpod providers are hand-written until this is
revisited. See `HANDOFF.md` (T0) and `DECISIONS.md`.
