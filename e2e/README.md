# Browser end-to-end test

Proves the cross-container flow that ties the deploy together:

```
entry (auth) ──signed iframe URL──▶ league container (NBA_REQUIRE_HANDOFF=1)
```

The entry point authenticates the customer, resolves their manager
(`competitor_id`) from `fty.customer_league`, and renders the league container in
an iframe with a signed, expiring URL. League containers run in strict mode
(`NBA_REQUIRE_HANDOFF=1`): a request without a valid token shows "Sign in
required" instead of the dashboard. The signature is the app-level security
boundary — Hugging Face does not enforce it.

This test drives a real browser to confirm login → choose a league → signed
iframe → dashboard renders *as the mapped manager* → switching to another league
from the dashboard's own **League** button, and that a bad/missing token is
rejected. The entry point has no persistent top bar: the customer chooses from a
modal league switcher (the dashboard's button reopens the same switcher via
`postMessage`).

## Run

```bash
cd e2e
npm install                       # playwright (set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
                                  # if you'll use the installed Chrome channel)

set -a; source ~/.config/scs_e2e.env; set +a   # E2E_PASSWORD lives here, not in the repo

# Single account
E2E_EMAIL=customer@example.com E2E_EXPECT_COMPETITORS='{"ESPN:123456":"7"}' npm test

# All customers with current-season league links
E2E_EMAILS="$(Rscript export_customers.R)" npm test
```

`export_customers.R` queries `fty.customer` joined to `fty.customer_league` and
`fty.league` for `core::nba_season()`. It emits only customer emails whose password
hash and competitor mapping are present. The harness uses the shared
`E2E_PASSWORD` for every account and handles both single-league (auto-embedded)
and multi-league (chooser) customers.

Credentials are kept in `~/.config/scs_e2e.env` (git-ignored, outside the repo);
the harness sources that file and never prints emails, passwords, or hashes.

- Uses the installed **Google Chrome** (`channel: "chrome"`), so no Playwright
  browser download is required.
- `E2E_EMAILS` accepts comma/newline-separated emails; `E2E_EMAIL` is the
  single-account fallback.
- `E2E_EXPECT_COMPETITORS` is optional and applies only in single-account mode.
  With multiple accounts, the dashboard title is verified but the per-league
  competitor expectation is skipped because the same league can map to different
  competitors for different customers.
- Screenshots and a JSON summary (including console errors) are written under
  `e2e/shots/`; results are identified by account index, not email. Exit code is
  non-zero if any league fails.
- `E2E_HEADLESS=0` runs headed.
- Credentials must be supplied via env and must **not** be committed. Each test
  customer's `fty.customer.password_hash` must be set (the real-password path;
  the `NBA_ENTRY_DEV` bypass is off on hosted Spaces).

## Implementation notes (gotchas)

- A single-league customer has no chooser: the entry auto-loads
  `iframe#league_frame`, and the harness reads the league from the iframe URL.
  Multi-league customers use the selectize chooser.
- The league chooser is a **selectize** control in the entry's modal: the native
  `select#league_choice` is `display:none`, so Playwright's `selectOption` does
  not work. Set the value via
  `select#league_choice.selectize.setValue(value, false)`, then click
  `#league_choose_confirm`.
- selectize may remove non-selected options from the native `<select>`; read the
  offered leagues from `selectize.options`, not from the `<select>` DOM.
- The entry renders a single `iframe#league_frame`; its `src` is replaced on every
  switch — wait for it to contain both `sig=` and `league_id=<id>` before reading
  it.
- Switching leagues again uses the dashboard's own `#fty_league_competitor_switch`
  button (inside the league frame), which asks the entry to reopen the chooser via
  `postMessage`.
- Cross-origin frames are readable by Playwright; pick the frame whose URL starts
  with the league Space origin.
- Success signal inside the league frame: a navbar title of the form
  `"<league> - <competitor>"`. Failure signal: the body contains
  `"Sign in required"`.

See `docs/NUC_DEPLOY.md` for Space secrets/variables.
