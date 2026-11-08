test_that("free agents get the earliest remaining matchup window per league", {
  df <- tibble(
    league_id = c("1", "1", "1", "1", "2", "2"),
    competitor_id = c("1", "2", "1", "free_agent", "1", "free_agent"),
    matchup_start = as.Date(c("2026-10-19", "2026-10-26", "2027-04-12", NA, "2026-11-02", NA)),
    matchup_end = as.Date(c("2026-10-25", "2026-11-01", "2027-04-11", NA, "2026-11-08", NA))
  )

  out <- fill_free_agent_window(df)
  fa <- filter(out, competitor_id == "free_agent")

  expect_equal(fa$matchup_start, as.Date(c("2026-10-19", "2026-11-02")))
  expect_equal(fa$matchup_end, as.Date(c("2027-04-11", "2026-11-08")))
  expect_true(all(fa$matchup_start <= fa$matchup_end))
})

test_that("starting slots count and bench/IR do not", {
  expect_true(all(is_starting_lineup(c("PG", "SG", "SF", "PF", "C", "UT", "G/F", "PF/C"))))
  expect_false(any(is_starting_lineup(c("BE", "IR", ""))))
})

test_that("an unknown lineup slot counts as starting", {
  expect_true(is_starting_lineup(NA_character_))
  expect_equal(is_starting_lineup(c(NA, "BE", "C")), c(TRUE, FALSE, TRUE))
})
