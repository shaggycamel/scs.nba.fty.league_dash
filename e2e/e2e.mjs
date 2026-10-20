import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

// Browser end-to-end test: entry login -> league chooser -> signed iframe ->
// league dashboard, then switching leagues from the dashboard's own button.
//
// Env:
//   E2E_PASSWORD                   (required) shared test-customer password
//   E2E_EMAILS                     (optional) comma/newline-separated customer emails
//   E2E_EMAIL                      (optional) single-customer fallback
//   ENTRY_URL                      (default https://shaggycamel-entry.hf.space/)
//   E2E_EXPECT_COMPETITORS         (optional) JSON map {"ESPN:<league_id>":"<competitor_id>"}
//   E2E_HEADLESS                   (default "1"; set "0" to watch)

const ENTRY = process.env.ENTRY_URL || "https://shaggycamel-entry.hf.space/";
const PASSWORD = process.env.E2E_PASSWORD;
const EMAILS = (process.env.E2E_EMAILS || process.env.E2E_EMAIL || "")
  .split(/[\s,]+/)
  .map((value) => value.trim())
  .filter(Boolean);
const EXPECTED = process.env.E2E_EXPECT_COMPETITORS
  ? JSON.parse(process.env.E2E_EXPECT_COMPETITORS)
  : {};
const HEADLESS = process.env.E2E_HEADLESS !== "0";

if (!EMAILS.length || !PASSWORD) {
  console.error("set E2E_PASSWORD and E2E_EMAILS or E2E_EMAIL");
  process.exit(2);
}

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SHOTS = path.join(HERE, "shots");
fs.mkdirSync(SHOTS, { recursive: true });

const results = [];
const consoleErrors = [];

const browser = await chromium.launch({ channel: "chrome", headless: HEADLESS });

const setLeagueSelect = (page, value) =>
  page.evaluate((val) => {
    const el = document.querySelector("select#league_choice");
    if (el && el.selectize && typeof el.selectize.setValue === "function") {
      el.selectize.setValue(val, false);
    } else if (el) {
      el.value = val;
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }, value);

const chooseLeague = async (page, value) => {
  await setLeagueSelect(page, value);
  await page.click("#league_choose_confirm");
};

const leagueFrame = (page, origin) =>
  page.frames().find((frame) => frame.url().startsWith(origin));

async function checkLeague(page, value, entry, account) {
  const leagueId = value.split(":")[1];
  await page.waitForFunction(
    (id) => {
      const frame = document.querySelector("iframe#league_frame");
      return !!frame && frame.src.includes("sig=") && frame.src.includes(`league_id=${id}`);
    },
    leagueId,
    { timeout: 30000 }
  );
  const src = await page.$eval("iframe#league_frame", (frame) => frame.src);
  const query = new URL(src).searchParams;
  entry.competitor_id = query.get("competitor_id");
  entry.has_sig = !!query.get("sig");
  entry.has_exp = !!query.get("exp");
  if (!entry.has_sig || !entry.has_exp) entry.notes.push("missing sig/exp");
  if (EMAILS.length === 1 && EXPECTED[value] && entry.competitor_id !== EXPECTED[value]) {
    entry.notes.push(`competitor ${entry.competitor_id} != expected ${EXPECTED[value]}`);
  }

  const origin = new URL(src).origin;
  let frame = null;
  for (let i = 0; i < 60 && !frame; i++) {
    frame = leagueFrame(page, origin);
    if (!frame) await page.waitForTimeout(1000);
  }

  if (!frame) {
    entry.notes.push("league frame not found");
  } else {
    let verdict = "unknown";
    for (let i = 0; i < 90; i++) {
      const body = await frame.locator("body").innerText().catch(() => "");
      if (/Sign in required/i.test(body)) {
        verdict = "sign-in-required";
        break;
      }
      const title = await frame
        .locator("#navbar_title, .navbar-brand, [id^=navbar_title]")
        .first()
        .innerText()
        .catch(() => "");
      if (title && title.trim()) {
        verdict = "dashboard:" + title.trim();
        break;
      }
      await page.waitForTimeout(1000);
    }
    entry.verdict = verdict;
    if (verdict === "sign-in-required") entry.notes.push("handoff rejected");
    if (verdict === "unknown") entry.notes.push("no dashboard detected");

    if (verdict.startsWith("dashboard:")) {
      const overview = frame.getByText("Overview", { exact: true }).first();
      if (await overview.count()) {
        await overview.click();
        const trend = frame.getByText("Category Trend", { exact: true }).first();
        if (await trend.count()) {
          await trend.click();
          await page.waitForTimeout(1500);
          const trendBody = await frame.locator("body").innerText().catch(() => "");
          const shinyErrors = await frame.locator(".shiny-error").count().catch(() => 0);
          if (shinyErrors > 0 || /could not find function/i.test(trendBody)) {
            entry.notes.push("category trend error");
          }
        } else {
          entry.notes.push("category trend tab not found");
        }
      } else {
        entry.notes.push("overview nav not found");
      }

      const comparison = frame.getByText("Player Comparison", { exact: true }).first();
      if (await comparison.count()) {
        await comparison.click();
        await page.waitForTimeout(1500);
        const comparisonBody = await frame.locator("body").innerText().catch(() => "");
        const comparisonErrors = await frame.locator(".shiny-error").count().catch(() => 0);
        if (
          comparisonErrors > 0 ||
          /Column .*doesn't exist|Column .*does not exist|could not find function/i.test(comparisonBody)
        ) {
          entry.notes.push("player comparison error");
        }
      } else {
        entry.notes.push("player comparison nav not found");
      }
    }
  }

  entry.ok = Boolean(
    entry.verdict && entry.verdict.startsWith("dashboard:") && entry.notes.length === 0
  );
  await page
    .screenshot({
      path: path.join(
        SHOTS,
        `account${account}_${value.replace(/[^a-z0-9]+/gi, "_")}.png`
      ),
    })
    .catch(() => {});
}

async function runAccount(page, email, account) {
  await page.goto(ENTRY, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForSelector("#email", { timeout: 60000 });
  await page.fill("#email", email);
  await page.fill("#password", PASSWORD);
  await page.click("#login");

  await page.waitForFunction(
    () => {
      const message = document.querySelector("#login_message")?.textContent.trim();
      return Boolean(
        message ||
          document.querySelector("select#league_choice") ||
          document.querySelector("iframe#league_frame")
      );
    },
    null,
    { timeout: 60000 }
  );
  const loginMessage = await page.textContent("#login_message").catch(() => "");
  if (loginMessage?.trim()) throw new Error("login failed: " + loginMessage.trim());

  const hasChooser = await page.locator("select#league_choice").count();
  const hasIframe = await page.locator("iframe#league_frame").count();
  let leagueList = [];
  let alreadySelected = false;

  if (hasChooser) {
    await page.waitForSelector("select#league_choice", { state: "attached", timeout: 60000 });
    await page.screenshot({ path: path.join(SHOTS, `account${account}_chooser.png`) });
    leagueList = await page.evaluate(() => {
      const el = document.querySelector("select#league_choice");
      return el && el.selectize ? Object.keys(el.selectize.options) : [];
    });
    console.log(`account ${account}: leagues offered`, JSON.stringify(leagueList));
  } else if (hasIframe) {
    await page.waitForFunction(
      () => {
        const frame = document.querySelector("iframe#league_frame");
        return !!frame && frame.src.includes("sig=") && frame.src.includes("league_id=");
      },
      null,
      { timeout: 30000 }
    );
    const src = await page.$eval("iframe#league_frame", (frame) => frame.src);
    const query = new URL(src).searchParams;
    const platform = query.get("platform") || "ESPN";
    const leagueId = query.get("league_id");
    leagueList = [`${platform}:${leagueId}`];
    alreadySelected = true;
    console.log(`account ${account}: single league`, leagueList[0]);
  } else {
    results.push({ account, league: null, ok: true, notes: ["no leagues offered"] });
    return;
  }

  if (!leagueList.length) {
    results.push({ account, league: null, ok: true, notes: ["no leagues offered"] });
    return;
  }

  for (let i = 0; i < leagueList.length; i++) {
    const value = leagueList[i];
    const entry = { account, league: value, ok: false, notes: [] };
    try {
      if (i > 0) {
        const prevSrc = await page.$eval("iframe#league_frame", (frame) => frame.src);
        const prevOrigin = new URL(prevSrc).origin;
        const frame = leagueFrame(page, prevOrigin);
        if (!frame) throw new Error("previous league frame not found");
        await frame.click("#fty_league_competitor_switch");
        await page.waitForSelector("select#league_choice", {
          state: "attached",
          timeout: 30000,
        });
      }

      if (!(alreadySelected && i === 0)) {
        await chooseLeague(page, value);
      }

      await checkLeague(page, value, entry, account);
    } catch (e) {
      entry.notes.push("error: " + e.message);
      entry.ok = false;
    }
    console.log(JSON.stringify(entry));
    results.push(entry);
  }
}

for (let i = 0; i < EMAILS.length; i++) {
  const account = i + 1;
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(`account ${account}: ${message.text()}`);
  });
  page.on("requestfailed", (request) =>
    consoleErrors.push(`account ${account}: reqfail: ${request.url()} ${request.failure()?.errorText}`)
  );
  try {
    await runAccount(page, EMAILS[i], account);
  } catch (e) {
    results.push({ account, league: null, ok: false, notes: ["fatal: " + e.message] });
  } finally {
    await page.close();
  }
}

await browser.close();

console.log("=== SUMMARY ===");
console.log(
  JSON.stringify(
    { results, consoleErrors: consoleErrors.slice(0, 50) },
    null,
    2
  )
);
process.exitCode = results.some((result) => !result.ok) ? 1 : 0;
