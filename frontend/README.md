# SmartEMS — Flutter frontend

Flutter client for Smart EMS, targeting Android and Web.

## Local development against the backend

The backend is Spring Boot in Docker at `http://localhost:8080`.

**The web app runs on port 3000.** Always:

```
flutter run -d chrome --web-port=3000
```

A fixed port matters: it keeps the dev origin stable at
`http://localhost:3000`, which is what lets the backend allowlist it.
Port 3000 is dev tooling only — it is never hardcoded in `lib/`.

Port 3000 is **not optional**: the backend's CORS allowlist accepts
`http://localhost:3000` specifically (verified 2026-07-30 — see
`BACKEND_CONTRACT.md`). On any other port the browser blocks the calls.
Port 3000 is dev tooling only — it is never hardcoded in `lib/`.

**Do not pass `--disable-web-security`.** It is not needed: CORS works on
port 3000. Disabling web security would hide genuine CORS regressions until
deployment.

VS Code launch configs in `.vscode/launch.json`:

- **SmartEMS (Chrome, port 3000)**
- **SmartEMS (Android/default device)**

## Token enforcement

Run before committing:

```
bash tool/check_tokens.sh
```

This fails if any file under `lib/` (except `lib/core/theme/`) uses a raw
colour, spacing, or radius value instead of the token scale.
