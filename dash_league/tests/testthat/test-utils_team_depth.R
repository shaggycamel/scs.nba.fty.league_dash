depth_rows <- function(teams, dates) {
  tibble(
    team_abbreviation = teams,
    game_date = as.Date(dates),
    position = "PG",
    player_id = seq_along(teams),
    player_name = teams,
    expected_minutes = 10
  )
}

test_that("the snapshot uses each team's nearest upcoming date, counting today", {
  df <- depth_rows(
    c("BOS", "BOS", "BOS", "LAL"),
    c("2026-11-20", "2026-11-21", "2026-11-25", "2026-11-19")
  )

  out <- team_depth_snapshot(df, as.Date("2026-11-21"))

  expect_equal(filter(out, team_abbreviation == "BOS")$game_date, as.Date("2026-11-21"))
  expect_equal(filter(out, team_abbreviation == "LAL")$game_date, as.Date("2026-11-19"))
})

test_that("the snapshot falls back to the latest date when no game remains", {
  df <- depth_rows(
    c("BOS", "BOS", "LAL", "LAL"),
    c("2026-11-18", "2026-11-19", "2026-10-30", "2026-11-02")
  )

  out <- team_depth_snapshot(df, as.Date("2026-11-21"))

  expect_equal(filter(out, team_abbreviation == "BOS")$game_date, as.Date("2026-11-19"))
  expect_equal(filter(out, team_abbreviation == "LAL")$game_date, as.Date("2026-11-02"))
})
