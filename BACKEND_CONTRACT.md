# Backend Contract

Pending seeding by the project owner (Ali owns the backend; Sami will
supply verified contract details). Do not populate this with guessed
endpoints — an invented list is worse than an empty one.

## Verified endpoints

_(endpoint list still pending seeding — nothing below is an endpoint claim)_

### CORS — VERIFIED 2026-07-30 against the running API

Method: live `curl` preflights against `http://localhost:8080` with the
backend booted from `SmartEMS/backend` (15 Flyway migrations applied,
`Started SmartEmsApplication in 48.994 seconds`). Not inferred from source.

| Fact | Observed |
|------|----------|
| Allowed origin | `Access-Control-Allow-Origin: http://localhost:3000` |
| Allowed methods | `GET,POST,PUT,PATCH,DELETE,OPTIONS` |
| Allowed headers | `authorization, content-type` |
| Preflight max age | `Access-Control-Max-Age: 3600` |
| Non-allowlisted origin | `403`, **no** `Access-Control-Allow-Origin` |
| `Access-Control-Allow-Credentials` | **absent** — see note below |

Evidence:

```
$ curl -i -X OPTIONS http://localhost:8080/ \
    -H "Origin: http://localhost:3000" -H "Access-Control-Request-Method: GET"
HTTP/1.1 200
Access-Control-Allow-Origin: http://localhost:3000
Access-Control-Allow-Methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
Access-Control-Max-Age: 3600

$ curl -i -X OPTIONS http://localhost:8080/ \
    -H "Origin: http://evil.example.com" -H "Access-Control-Request-Method: GET"
HTTP/1.1 403          <- no CORS header: a real allowlist, not a wildcard echo
```

Consequences for the frontend:

- The web app **must** run on port 3000 (`--web-port=3000`). Any other port
  is blocked by the browser.
- `--disable-web-security` is **not needed and must not be used**.
- `Authorization` is an allowed request header, so a **bearer-token** auth
  scheme works cross-origin.
- **`Access-Control-Allow-Credentials` is absent.** Cookie / session-based
  auth will therefore NOT work cross-origin from `localhost:3000`. If T7
  turns out to need cookies, this must be raised with Ali rather than worked
  around on the client. Do not assume credentials are supported.
- All paths tried returned `401` unauthenticated (Spring Security is on by
  default), including `/actuator/health`. Preflight `OPTIONS` is permitted
  without auth.

## Known gaps

_(none yet — pending seeding)_

## Never assume

- Never assume `Access-Control-Allow-Credentials` is supported. It was
  measured as **absent** (see Verified endpoints). Cookie-based auth will
  not work cross-origin.
- Never assume the web app can run on a port other than 3000 in
  development. The CORS allowlist is origin-exact.

### Running the backend locally — gotchas found 2026-07-30

Recorded because two of these cost real time and neither is guessable:

1. **`docker-compose.yml` in `SmartEMS/backend` defines only the `db`
   service.** There is no `app` service, so `docker compose up -d --build`
   brings up Postgres only and `--build` has nothing to build. The app is a
   separate container.
2. **The prebuilt `smart-ems-backend:local` image defaults its datasource to
   `localhost:5432`**, which inside the container is the container itself →
   `Connection refused`. It also sets Flyway's URL independently, so
   `SPRING_DATASOURCE_URL` alone is not enough. What actually worked:
   ```
   docker run -d --name smart-ems-app --network backend_default -p 8080:8080 \
     -e SPRING_DATASOURCE_URL='jdbc:postgresql://db:5432/smartems' \
     -e SPRING_DATASOURCE_USERNAME='smartems' \
     -e SPRING_DATASOURCE_PASSWORD='localdev' \
     -e SPRING_FLYWAY_URL='jdbc:postgresql://db:5432/smartems' \
     -e SPRING_FLYWAY_USER='smartems' \
     -e SPRING_FLYWAY_PASSWORD='localdev' \
     smart-ems-backend:local
   ```
3. **`docker build` of the backend currently FAILS on Windows** —
   `./gradlew: not found`, exit 127, despite the file existing.
   Cause: `gradlew` is checked out with **CRLF** line endings
   (`#!/bin/sh\r\n`), so Linux looks for the interpreter `/bin/sh\r`.
   This is a backend-repo issue for Ali (`.gitattributes` with
   `gradlew text eol=lf`, or `dos2unix gradlew`). **Not fixed here** —
   frontend work must not edit `backend/`. The image built 10 days ago was
   used instead, so the CORS result above stands, but the app image cannot
   currently be rebuilt from source on this machine.
4. The earlier stale-mount failure is **resolved**: `docker compose config`
   from `SmartEMS/backend` now resolves `init.sql` to
   `E:\Business Work\Babultech\SmartEMS\backend\docker\init.sql`, which
   exists. The old error came purely from containers created while the
   backend lived at `ERP working\smart-ems-backend`. No hardcoded absolute
   path in the compose file. Note the compose project name is now `backend`,
   so the volume is `backend_pgdata` — a fresh database, not the old
   `smart-ems-backend_pgdata`.

- Never assume an endpoint, request/response shape, auth mechanism, or
  error format exists unless it is listed above or confirmed directly by
  Ali.
- Never assume the backend is reachable at a given URL without
  independent confirmation (see `CLAUDE.md` for the current, unverified
  local dev URL).
- Never read `backend/` (the local clone at the repo root) as a source of
  truth. It exists only as a runtime dependency, to run the API locally
  for development. This contract is verified against the running API's
  observed behaviour, not by reading backend source code.
