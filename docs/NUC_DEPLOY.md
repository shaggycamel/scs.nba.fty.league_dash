# NUC Deployment Runbook

Instructions for an agent operating on the **nuc** host to build and deploy the
NBA Shiny league containers and entry point to Hugging Face Spaces.

Read this whole file before running anything. Prefer `DRY_RUN=1` first.

---

## 1. Context

- Repo: `scs.nba.fty.league_dash` (monorepo; the league dashboard is the `dash_league/`
  package, which holds `data-raw/` and is built from its own directory).
- Sibling packages: `dash_core/` (shared theme/db/token/password) and
  `dash_entry/` (the **entry point**: auth → league picker → signed iframe).
- Containers are built from Docker images and deployed as **one HF Space per league**
  plus a single **entry Space**. League containers bake their data at build time;
  the entry point reads customer/league data from CockroachDB at runtime.
- Deploy logic lives in `deploy/`: `cron.sh` (the single deploy entry point: base
  image + leagues, plus the entry point when `BUILD_ENTRY=1`), `build_entry.sh`
  (entry only), and the provider adapter (currently Hugging Face).

## 2. Prerequisites (verify before starting)

- Docker is running and can reach Docker Hub.
- **No host R/renv is needed.** All R steps (data generation, `R CMD build`, league
  listing) run inside the `scs.nba.fty.league_dash_base:latest` image, which carries the restored
  library. (The host must have Docker; R is used via `docker run`.)
- Credentials INI exists: `~/.config/scs_hub_credentials.ini` with a
  `cockroach-read` section (and `postgres` for local). Generation defaults to
  `NBA_DB_SECTION=cockroach-read`. (No `psql` needed — leagues are listed via R in
  the base image.) The dashboard update log also needs a `cockroach-write`
  section, unless `NBA_UPDATE_LOG_SECTION` points elsewhere.
- A `./.profile` on the nuc exports the tokens (the scripts source it
  automatically when run non-interactively; for a manual run, source it first):
  - `DOCKERHUB_TOKEN` — Docker Hub push token (required).
  - `HUGGINGFACE_TOKEN` — HF token with **write** access to the Spaces (required).
  - `DOCKERHUB_USER` (default `shaggycamel`) and `NBA_HF_OWNER` (default `shaggycamel`).

  The shared handoff key lives outside the repo in
  `~/.config/scs_hf_league_deploy.ini` (mode `600`):

  ```ini
  [handoff]
  NBA_HANDOFF_SECRET=<64 hex characters>
  ```

  The current season is defined only in `core::nba_season()`; do not configure
  `NBA_SEASON` in `.profile` or Hugging Face Space variables.

  Create it once (git-ignored, never commit):
  ```bash
  cat > ~/shaggy_camel_sports/nba/fty/league_dash/.profile <<'EOF'
  export DOCKERHUB_USER=shaggycamel
  export DOCKERHUB_TOKEN=...
  export HUGGINGFACE_TOKEN=...
  EOF
  chmod 600 ~/shaggy_camel_sports/nba/fty/league_dash/.profile
  ```

Preflight:

```bash
cd ~/shaggy_camel_sports/nba/fty/league_dash
git pull                      # MUST be up to date; see §3
docker info >/dev/null && echo docker-ok
test -f ~/.config/scs_hub_credentials.ini && echo ini-ok
test -f ~/.config/scs_hf_league_deploy.ini && echo handoff-ini-ok
set -a; source ./.profile; set +a
for v in DOCKERHUB_TOKEN HUGGINGFACE_TOKEN; do
  [ -n "${!v:-}" ] && echo "$v set" || echo "$v MISSING"
done
# League listing runs inside the base image, so do it after the base is built
# (or just rely on the dry run in §5, which exercises the same code path).
```

## 3. Code must be pushed first

The build uses the checked-out code. If the developer's changes are not yet on the
remote, `git pull` will not include them — do not proceed on stale code. Confirm
`git log --oneline -1` matches the commit the developer reported.

## 4. Values

Owner defaults to `shaggycamel`; Space prefix is empty; image prefix is
`scs.nba.fty.league_dash-`.

| Purpose | HF Space | URL |
|--------|----------|-----|
| Entry point | `shaggycamel/entry` | `https://shaggycamel-entry.hf.space` |
| League ESPN 95537 | `shaggycamel/espn-95537` | `https://shaggycamel-espn-95537.hf.space` |
| League ESPN 1440301458 | `shaggycamel/espn-1440301458` | `…-espn-1440301458.hf.space` |
| League ESPN 1484259390 | `shaggycamel/espn-1484259390` | `…-espn-1484259390.hf.space` |
| League ESPN 1966813226 | `shaggycamel/espn-1966813226` | `…-espn-1966813226.hf.space` |

Active leagues are read from `fty.league` for `core::nba_season()`; this table is
illustrative. The retired `espn-1382487116` and `espn-24608` Spaces are not part
of 2026-27 and are not deployed.

Docker images: `shaggycamel/scs.nba.fty.league_dash-espn-<league_id>:latest`; entry
`shaggycamel/scs.nba.fty.league_dash_entry:latest`. Base image: `scs.nba.fty.league_dash_base:latest`.

`NBA_HANDOFF_SECRET` is an arbitrary shared HMAC key (no default). It lives only
in `~/.config/scs_hf_league_deploy.ini` (mode `600`), never in the repo or
`.profile`. The deploy adapter reads it to configure and rotate Spaces.

## 5. Build + deploy

Run from the repo root. Source the tokens first, and always dry-run first.

When `dash_core` changes (including the season), rebuild the base image before
the dry run so the league list uses the new code, or use `REBUILD_BASE=1`:

```bash
docker build -f ./docker/Dockerfile_base --progress=plain -t scs.nba.fty.league_dash_base:latest .
```

```bash
set -a; source ./.profile; set +a

# 5.0 Dry run (no docker, no push, no deploy)
DRY_RUN=1 PROVISION=1 bash deploy/cron.sh

# 5.1 Real run. PROVISION=1 creates any missing HF Spaces.
PROVISION=1 bash deploy/cron.sh

# 5.2 Full run including the entry point (this restarts the entry Space).
PROVISION=1 BUILD_ENTRY=1 bash deploy/cron.sh

# 5.3 Cadence runs (as cron): a bare run is 'all'; the arg only labels the
# util.update_log rows. daily builds the base, intraday reuses the cached base.
PROVISION=1 bash deploy/cron.sh daily
SKIP_BASE=1 PROVISION=1 bash deploy/cron.sh intraday
```

`deploy/cron.sh` does, in order:
1. Base image `scs.nba.fty.league_dash_base:latest` (slow; skipped if it exists unless `REBUILD_BASE=1`)
   and verifies `core` loads in it.
2. Generates the shared NBA base once, then per league generates data, builds the
   tarball, builds/pushes `shaggycamel/scs.nba.fty.league_dash-<slug>:latest`, and deploys.
   Failures are reported per league; the loop continues.
3. `deploy/build_entry.sh` — builds/pushes/deploys `shaggycamel/scs.nba.fty.league_dash_entry:latest` —
   only when `BUILD_ENTRY=1` (rebuilding restarts the entry Space).

### Dashboard update log

Each stage appends `dashboard:*` rows to `util.update_log` (the same table
`database/__main__.py` writes), so a run is auditable without reading the cron log:

| `task` | Written |
|--------------|---------|
| `dashboard start` / `dashboard end` | Once per run (bookends); `end` is a failure unless the whole run succeeded |
| `dashboard:base` | After the shared NBA base is (re)generated (not on `SKIP_BASE=1` reuse) |
| `dashboard:<slug>` | Per league, e.g. `dashboard:espn-95537`; a failure carries the stage that broke |
| `dashboard:entry` | When `BUILD_ENTRY=1` |

The run's cadence argument is stamped on every row's `cadence` column
(`daily`/`intraday`/`all`), mirroring `database/cron.sh`. Every row also carries
`source` — this repo's name, derived from the checkout's git remote (override
with `UPDATE_LOG_SOURCE`) — and `job_kickoff`, the run's start time, identical on
all rows of a run so a run can be grouped. Logging is best-effort: a failed write
only warns, and `DRY_RUN=1` skips it. It writes with the `cockroach-write`
section (override with `NBA_UPDATE_LOG_SECTION`).

> Since `core` gained `log_update()`, rebuild the base image once
> (`REBUILD_BASE=1`) so the deploy containers have the new function; until then
> the log writes warn and are skipped. The write includes `source` and
> `job_kickoff`, so the target `util.update_log` must have those columns (see
> `INSTRUCTIONS_update_log_source_kickoff.md` in the `database` repo).

Individual stages (if you need to isolate a failure):

```bash
REBUILD_BASE=1 bash deploy/cron.sh          # force base rebuild
BUILD_ENTRY=1 bash deploy/cron.sh           # also rebuild/deploy the entry point
PROVISION=1 bash deploy/build_entry.sh      # entry only
```

## 6. Space configuration

`deploy/hf.sh` configures Spaces through the HF API during provisioning and
deployment. It reads the shared handoff key from
`~/.config/scs_hf_league_deploy.ini` (mode `600`):

```ini
[handoff]
NBA_HANDOFF_SECRET=<64 hex characters>
```

- Entry: ensures `NBA_HANDOFF_SECRET` only. The entry's `NBA_DB_HOST`,
  `NBA_DB_USER`, `NBA_DB_PASSWORD`, `NBA_DB_PORT`, and `NBA_DB_NAME` secrets are
  pre-existing and managed separately.
- League Spaces: ensures `NBA_HANDOFF_SECRET` and `NBA_REQUIRE_HANDOFF=1`.
- Never set `NBA_SEASON` or `NBA_DB_SECTION` on a Space; the season comes only
  from `core::nba_season()`.
- Leagues found by `PROVISION=1` are created and configured automatically.

Normal runs add a missing secret or variable only. To rotate the shared handoff
key, update the INI and set `ROTATE_HANDOFF_SECRET=1` for the run:

```bash
ROTATE_HANDOFF_SECRET=1 PROVISION=1 BUILD_ENTRY=1 bash deploy/cron.sh
```

Rotation restarts the affected Spaces; entry and every league must use the same
key.

Remove legacy variables once with the adapter helpers (this restarts each Space):

```bash
set -a; source ./.profile; set +a
source deploy/adapter.sh
for slug in entry espn-95537 espn-1966813226; do
  repo="$(hf_space_id "$slug")"
  role=league; [ "$slug" = entry ] && role=entry
  hf_cleanup_legacy_vars "$repo" "$role"
done
```

This removes `NBA_SEASON` from each Space and, for entry only, the redundant
`NBA_DB_SSLMODE` and `NBA_HF_SPACE_PREFIX` variables.

Secrets and variables take effect after a Space restart; the deploy step in §5
already restarts Spaces.

## 7. Set customer passwords

Passwords are stored hashed in `fty.customer.password_hash`. Set one per customer:

```bash
cd ~/shaggy_camel_sports/nba/fty/league_dash
NBA_DB_SECTION=cockroach-read NBA_SET_PASSWORD='<password>' \
  Rscript scripts/set_customer_password.R <customer_email>
```

`scripts/` is git-ignored; if it is missing, it was not synced (it is intentionally
not versioned).

## 8. Verify

```bash
# entry point serves a login page
curl -fsS -o /dev/null -w '%{http_code}\n' https://shaggycamel-entry.hf.space/

# each league Space is up (will show the "Sign in required" modal when
# NBA_REQUIRE_HANDOFF=1 and no token is present — that is correct)
curl -fsS -o /dev/null -w '%{http_code}\n' https://shaggycamel-espn-95537.hf.space/
```

Then, in a browser: open the entry URL → log in → pick a league → the league
dashboard should load inside the iframe, already scoped to that customer's manager.

## 9. Troubleshooting

- **Base build fails / `core` missing**: check `renv.lock` includes
  `openssl`, `digest`, `ini`, `bslib`, `DBI`, `RPostgres`. Rebuild with
  `REBUILD_BASE=1`.
- **"no leagues found"**: `fty.league` has no rows for `core::nba_season()`, or the
  credentials INI section is wrong. Debug inside the base image:
  `docker run --rm -v "$HOME/.config:/root/.config:ro" -v "$PWD:/work" -w /work/dash_league scs.nba.fty.league_dash_base:latest Rscript ./data-raw/_list_leagues.R`
- **HF restart returns non-2xx**: the Space does not exist (run with `PROVISION=1`)
  or `HUGGINGFACE_TOKEN` lacks write access.
- **401/blank league dashboard**: `NBA_HANDOFF_SECRET` differs between entry and the
  league Space, or is unset. They must match.
- **Manager not auto-selected**: `fty.customer_league.competitor_id` is NULL for that
  row; the entry point falls back to a manager picker.
- **Background/stop needed**: do not `docker system prune` on the nuc — the base image
  is expensive to rebuild.

## 10. Guardrails

- Never commit or echo secrets; do not add them to the repo or this file.
- Always `DRY_RUN=1` first when changing scripts.
- `PROVISION=1` is idempotent (creates missing Spaces, commits a Dockerfile only for
  new Spaces); it will not delete anything.
- Do not force-push or amend commits.
