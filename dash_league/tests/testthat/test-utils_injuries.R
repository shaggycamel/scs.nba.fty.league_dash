test_that("future injuries use each team's latest report", {
  injuries <- tibble(
    game_date = as.Date(c("2026-04-12", "2026-10-21", "2026-10-21", "2026-10-22", "2026-04-12")),
    team_slug = c("CLE", "CLE", "PHI", "CLE", "CLE"),
    nba_id = c(201935L, 201935L, 999L, 1628386L, 321L),
    status = c("Out", "Available", "Out", "Questionable", "Out"),
    reason = c("Rest", NA, "Ankle", "Knee", "Rest")
  )
  future <- tibble(
    team = c("CLE", "CLE", "PHI", "CLE", "CLE"),
    player_id = c(201935L, 1628386L, 999L, 123L, 321L)
  )

  out <- attach_current_injury_status(future, injuries, as.Date("2026-10-22"))

  expect_equal(
    out$inj_status,
    c("Available", "Questionable", "Out", "Available", "Available")
  )
  expect_equal(out$inj_reason, c(NA, "Knee", "Ankle", NA, NA))
})

test_that("predicted returns use the latest snapshot of the latest active spell", {
  forecasts <- tibble(
    player_id = c(1L, 1L, 1L, 2L, 2L),
    spell_id = c("a", "a", "b", "c", "c"),
    injury_start_date = as.Date(c(
      "2026-11-01",
      "2026-11-01",
      "2026-11-20",
      "2026-11-10",
      "2026-11-10"
    )),
    prediction_date = as.Date(c("2026-11-02", "2026-11-21", "2026-11-21", "2026-11-12", "2026-11-12")),
    pred_return_date = as.Date(c("2026-11-10", "2026-11-18", "2026-11-25", "2026-11-20", NA)),
    censored = c(TRUE, TRUE, TRUE, FALSE, TRUE)
  )

  out <- latest_predicted_return(forecasts)

  expect_equal(nrow(out), 1)
  expect_equal(out$player_id, 1L)
  expect_equal(out$pred_return_date, as.Date("2026-11-25"))
})

test_that("predicted status flips injured players on their return date", {
  df <- tibble(
    player_id = c(1L, 1L, 1L, 1L, 2L, 2L, 3L, 4L),
    game_date = as.Date(c(
      "2026-11-20",
      "2026-11-21",
      "2026-11-22",
      "2026-11-23",
      "2026-11-22",
      "2026-11-23",
      "2026-11-22",
      "2026-11-22"
    )),
    inj_status = c("Out", "Out", "Out", "Out", "Questionable", "Questionable", "Available", "Probable")
  )
  returns <- tibble(
    player_id = c(1L, 2L, 4L),
    pred_return_date = as.Date(c("2026-11-22", "2026-11-24", "2026-11-22"))
  )

  out <- attach_predicted_injury_status(df, returns, as.Date("2026-11-21"))

  expect_equal(
    out$inj_status_pred,
    c(
      "Out",
      "Out",
      "Available",
      "Available",
      "Questionable",
      "Questionable",
      "Available",
      "Probable"
    )
  )
})

test_that("the next-game status uses the earliest upcoming game", {
  df <- tibble(
    player_id = c(1L, 1L, 2L),
    game_date = as.Date(c("2026-11-23", "2026-11-22", "2026-11-19")),
    inj_status_pred = c("Available", "Out", "Out")
  )

  out <- next_game_injury_status(df, as.Date("2026-11-21"))

  expect_equal(out$player_id, 1L)
  expect_equal(out$inj_status_pred, "Out")
})
