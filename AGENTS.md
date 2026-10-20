# AGENTS.md

Monorepo for the NBA fantasy league dashboard: three R packages plus the
container/deploy pipeline. The app is a `{golem}` Shiny app.

## Layout

- `dash_league/` — league dashboard Shiny app. R package name: `league`. Holds `data-raw/`.
- `dash_entry/` — auth entry point (login → league picker → signed iframe). Package: `entry`.
- `dash_core/` — shared theme/db/token/password helpers. Package: `core`.
- `docker/`, `deploy/` — container build/deploy pipeline.
- `e2e/` — Playwright browser test (entry login → signed iframe → league).
- `docs/NUC_DEPLOY.md` — deployment runbook.

IMPORTANT: folders are prefixed `dash_`, but R package names stay
`core`/`entry`/`league`. Use `library(league)`, `Imports: core`, `run_app()`, etc.
`R CMD build` tarballs are named by the Package field (`league_*.tar.gz`), not the
folder.

## Develop

```r
renv::restore()
devtools::load_all("dash_league")
league::run_app()
```

## Test

Unit tests (testthat), run per package:

```r
devtools::test("dash_league")
devtools::test("dash_core")
devtools::test("dash_entry")
```

Browser end-to-end (Playwright) needs live Spaces and credentials, so it is not
part of the unit suite. Credentials live in `~/.config/scs_e2e.env`
(`E2E_EMAIL` / `E2E_PASSWORD`), never in the repo. See `e2e/README.md` for env
vars and gotchas:

```bash
cd e2e
npm install
set -a; source ~/.config/scs_e2e.env; set +a   # E2E_EMAIL / E2E_PASSWORD
npm test
```

## Format

`air format` (config in `air.toml`: 120-col, 2-space).

## Deploy

`deploy/cron.sh` is the single deploy entry point (base image + one image per
league; `BUILD_ENTRY=1` also rebuilds the entry Space). `deploy/build_entry.sh`
does entry only. It takes an optional cadence arg (`daily`/`intraday`, default
`all`) and appends best-effort `dashboard:*` rows to `util.update_log` via
`core::log_update()` (`cockroach-write`), each stamped with `source` (this repo's
name, from the git remote) and `job_kickoff` (the run start).
The HF adapter reads the shared handoff key from
`~/.config/scs_hf_league_deploy.ini` (mode 600), configures missing Space
secrets/variables, and rotates with `ROTATE_HANDOFF_SECRET=1`. New Spaces use
the `[space]` hardware/sleep settings (`cpu-upgrade`, 900s by default).
Always `DRY_RUN=1` first. Docker build context is the repo root; `.dockerignore`
excludes `dash_league/{data,data-raw,dev,tests,man}`, `docs/`, and `e2e/`.
Full runbook: `docs/NUC_DEPLOY.md` (load on demand — do not preload).

## Conventions / gotchas

- Never commit secrets. DB creds live in `~/.config/scs_hub_credentials.ini`;
  deploy tokens in `~/.config/scs_deploy.env` (mode 600); the handoff key in
  `~/.config/scs_hf_league_deploy.ini` (mode 600); e2e creds in
  `~/.config/scs_e2e.env`.
- Customer logins live in `fty.customer` (`email`, `password_hash`). E2E can
  iterate customers from `e2e/export_customers.R`; the shared test password comes
  from `~/.config/scs_e2e.env` or a git-ignored accounts file, never committed.
  Hashes are one-way; verify candidates with `core::verify_password`.
- `NBA_DB_SECTION` selects the build-time/local database. Space runtime uses
  `NBA_HANDOFF_SECRET` and `NBA_REQUIRE_HANDOFF`. The current season is defined
  only by `core::nba_season()`; do not set `NBA_SEASON` on Spaces.
- Handoff security: `entry` signs an HMAC token; league containers verify it.
  `NBA_HANDOFF_SECRET` must be identical on the entry and every league Space.
- `scripts/` is git-ignored. It holds `set_customer_password.R` (sets
  `fty.customer.password_hash`); run from the repo root with `NBA_DB_SECTION`
  selecting the DB (local `postgres`, hosted `cockroach-read`/`-write`).
- Customer login: `core::verify_password` handles bcrypt / pbkdf2 / argon2. The
  hosted entry authenticates against CockroachDB; local `postgres` can hold a
  different hash, so a password set locally may not work on HF.
- The `cockroach-read` user has `SELECT` on views and some tables but not all raw
  tables (e.g. `fty.matchup_result` needed an explicit `GRANT`). Views/grants are
  managed out-of-band in the sibling `database/` repo, not by this deploy.
- Don't add code comments unless asked.
