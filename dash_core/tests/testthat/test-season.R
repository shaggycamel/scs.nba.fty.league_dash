test_that("the season is defined centrally", {
  old <- Sys.getenv("NBA_SEASON", unset = NA)
  on.exit(
    if (is.na(old)) Sys.unsetenv("NBA_SEASON") else Sys.setenv(NBA_SEASON = old),
    add = TRUE
  )
  Sys.setenv(NBA_SEASON = "2025-26")

  expect_equal(nba_season(), "2026-27")
})
