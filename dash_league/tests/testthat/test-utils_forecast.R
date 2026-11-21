test_that("forecast stats map onto the box-score vocabulary", {
  forecast <- tibble(
    player_id = 1L,
    game_id = 10L,
    minutes_if_plays = 30,
    pred_fga = 12,
    pred_fgm = 6,
    pred_fg3a = 5,
    pred_fg3m = 2,
    pred_fta = 4,
    pred_ftm = 3,
    pred_oreb = 1,
    pred_dreb = 4,
    pred_ast = 5,
    pred_stl = 1,
    pred_blk = 0,
    pred_tov = 2,
    pred_pf = 3,
    pred_pts = 17,
    pred_reb = 5
  )

  out <- forecast_box_score_stats(forecast)

  expect_equal(
    names(out),
    c(
      "player_id",
      "game_id",
      "min",
      "fga",
      "fgm",
      "fg3_a",
      "fg3_m",
      "fta",
      "ftm",
      "oreb",
      "dreb",
      "ast",
      "stl",
      "blk",
      "tov",
      "pf",
      "pts",
      "reb"
    )
  )
  expect_equal(out$min, 30)
  expect_equal(out$fg3_a, 5)
  expect_equal(out$fg3_m, 2)
  expect_equal(out$pts, 17)
})
