game_days <- cur_date + 0:3
roster <- h2h_test_roster()
df_base <- fake_h2h_base(roster, game_days)
df_tbl <- table_data_prep(df_base, NULL, no_grey_players(), game_days[1])

test_that("one row per competitor, ordered descending", {
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1])

  expect_equal(sums$player_team, c("Us", "Them"))
  expect_true(all(is.na(sums$player_name)))
})

test_that("daily totals exclude players listed Out", {
  # Bob's "1*" cells are zeroed by the logical multiplier, so only Ann's games
  # reach his competitor's totals.
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1])
  us <- filter(sums, player_team == "Us")

  expect_equal(unname(unlist(select(us, contains("/")))), c(1, 0, 1, 1, 0, 0))
  expect_no_warning(table_sum_data_prep(df_tbl, df_base, game_days[1]))
})

test_that("games_remaining counts only available players", {
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1])

  # Ann 3; Bob's 3 are excluded because he is Out. Cyd 2 on her own.
  expect_equal(pull(sums, games_remaining, player_team), c(Us = 3, Them = 2))
})

test_that("a pin past the last game day leaves no games remaining", {
  expect_no_error(sums <- table_sum_data_prep(df_tbl, df_base, cur_date + 30))
  expect_equal(sums$games_remaining, c(0, 0))
})

test_that("a finished matchup leaves no games remaining", {
  past_days <- cur_date - 4:1
  past_base <- fake_h2h_base(roster, past_days)
  past_tbl <- table_data_prep(past_base, NULL, no_grey_players(), past_days[1])

  expect_equal(table_sum_data_prep(past_tbl, past_base, past_days[1])$games_remaining, c(0, 0))
})
