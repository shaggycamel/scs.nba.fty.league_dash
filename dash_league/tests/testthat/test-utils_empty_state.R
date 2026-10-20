test_that("placeholder text includes the regular season start", {
  expect_match(
    season_placeholder_text("2026-27", as.Date("2026-10-20")),
    "20 October 2026"
  )
})

test_that("placeholder text falls back when the start date is missing", {
  expect_match(
    season_placeholder_text("2026-27", NULL),
    "has not started yet"
  )
})
