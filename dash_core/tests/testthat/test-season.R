with_season <- function(value, code) {
  old <- Sys.getenv("NBA_SEASON", unset = NA)
  if (is.na(value)) {
    Sys.unsetenv("NBA_SEASON")
  } else {
    Sys.setenv(NBA_SEASON = value)
  }
  on.exit(
    if (is.na(old)) Sys.unsetenv("NBA_SEASON") else Sys.setenv(NBA_SEASON = old),
    add = TRUE
  )
  force(code)
}

test_that("NBA_SEASON overrides the default", {
  with_season("2026-27", expect_equal(nba_season(), "2026-27"))
})

test_that("an unset NBA_SEASON falls back to the default", {
  with_season(NA, expect_equal(nba_season(), "2025-26"))
})

test_that("an empty NBA_SEASON falls back to the default", {
  with_season("", expect_equal(nba_season(), "2025-26"))
})
