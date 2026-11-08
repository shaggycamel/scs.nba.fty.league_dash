test_that("check_credentials rejects empty input without touching the db", {
  expect_true(is.na(check_credentials(NULL, "", "")))
  expect_true(is.na(check_credentials(NULL, "a@b.com", "")))
  expect_true(is.na(check_credentials(NULL, "", "x")))
})

test_that("parse_league_value splits platform and id", {
  expect_equal(parse_league_value("ESPN:95537"), list(platform = "ESPN", league_id = 95537L))
})

test_that("league_space_url follows the deploy naming convention", {
  expect_equal(
    league_space_url("ESPN", 95537, owner = "shaggycamel", prefix = ""),
    "https://shaggycamel-espn-95537.hf.space"
  )
})

test_that("entry_allowed_origins derives container origins", {
  leagues <- data.frame(
    platform = c("ESPN", "ESPN"),
    league_id = c("1", "2"),
    league_name = c("A", "B"),
    competitor_id = c(NA_character_, NA_character_),
    slug = c(NA_character_, NA_character_),
    container_url = c(NA_character_, "https://example.test/"),
    stringsAsFactors = FALSE
  )

  origins <- entry_allowed_origins(leagues)
  expect_true("https://shaggycamel-espn-1.hf.space" %in% origins)
  expect_true("https://example.test" %in% origins)
  expect_equal(entry_allowed_origins(leagues[0, ]), character(0))
})

test_that("league_iframe_url carries a verifiable handoff token", {
  old <- Sys.getenv("NBA_HANDOFF_SECRET", unset = NA)
  Sys.setenv(NBA_HANDOFF_SECRET = "test-secret")
  on.exit(
    if (is.na(old)) Sys.unsetenv("NBA_HANDOFF_SECRET") else Sys.setenv(NBA_HANDOFF_SECRET = old),
    add = TRUE
  )

  now <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")
  url <- league_iframe_url(
    "https://example.hf.space",
    customer_id = "ACME",
    platform = "ESPN",
    league_id = 95537,
    competitor_id = 42,
    ttl = 300,
    now = now
  )

  expect_match(url, "^https://example\\.hf\\.space/\\?")
  params <- shiny::parseQueryString(sub("^[^?]*\\?", "", url))
  expect_true(core::verify_handoff_token(
    params$sig,
    params$customer_id,
    params$platform,
    params$league_id,
    params$competitor_id,
    params$exp,
    now = now
  ))
})
