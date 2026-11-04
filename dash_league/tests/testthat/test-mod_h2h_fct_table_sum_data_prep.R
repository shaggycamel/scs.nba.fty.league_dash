game_days <- cur_date + 0:3
roster <- h2h_test_roster()
df_base <- fake_h2h_base(roster, game_days)
df_tbl <- table_data_prep(df_base, NULL, no_grey_players(), game_days[1])

test_that("one row per competitor, ordered descending", {
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1], Inf)

  expect_equal(sums$player_team, c("Us", "Them"))
  expect_true(all(is.na(sums$player_name)))
})

test_that("daily totals exclude players listed Out", {
  # Bob's "1*" cells are zeroed by the logical multiplier, so only Ann's games
  # reach his competitor's totals.
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1], Inf)
  us <- filter(sums, player_team == "Us")

  expect_equal(unname(unlist(select(us, contains("/")))), c(1, 0, 1, 1, 0, 0))
  expect_no_warning(table_sum_data_prep(df_tbl, df_base, game_days[1], Inf))
})

test_that("games_remaining counts only available players", {
  sums <- table_sum_data_prep(df_tbl, df_base, game_days[1], Inf)

  # Ann 3; Bob's 3 are excluded because he is Out. Cyd 2 on her own.
  expect_equal(pull(sums, games_remaining, player_team), c(Us = 3, Them = 2))
})

test_that("games_remaining stops at matchup_end and ignores the post-matchup days", {
  # As in the player table: the two post-matchup days render after the total,
  # so they must not be added in.
  limited_base <- fake_h2h_base(
    roster,
    game_days,
    matchup_end = cur_date + 1,
    matchup_end_plus = cur_date + 3
  )
  limited_tbl <- table_data_prep(limited_base, NULL, no_grey_players(), game_days[1])
  sums <- table_sum_data_prep(limited_tbl, limited_base, game_days[1], Inf)

  expect_equal(pull(sums, games_remaining, player_team), c(Us = 1, Them = 1))
})

test_that("a pin past the last game day leaves no games remaining", {
  expect_no_error(sums <- table_sum_data_prep(df_tbl, df_base, cur_date + 30, Inf))
  expect_equal(sums$games_remaining, c(0, 0))
})

test_that("a finished matchup leaves no games remaining", {
  past_days <- cur_date - 4:1
  past_base <- fake_h2h_base(roster, past_days)
  past_tbl <- table_data_prep(past_base, NULL, no_grey_players(), past_days[1])

  expect_equal(table_sum_data_prep(past_tbl, past_base, past_days[1], Inf)$games_remaining, c(0, 0))
})

test_that("games_remaining caps each day at the league's lineup spots", {
  # Three available players play the first day and two the second. A team can
  # only use its lineup spots, so with two spots the total is 2 + 2, not 3 + 2.
  capped_roster <- list(
    fake_player(1, "Ann", "LAL", "Us", c(1, 1, 0)),
    fake_player(2, "Bob", "BOS", "Us", c(1, 0, 0)),
    fake_player(3, "Cyd", "NYK", "Us", c(1, 1, 0))
  )
  capped_base <- fake_h2h_base(capped_roster, game_days[1:3])
  capped_tbl <- table_data_prep(capped_base, NULL, no_grey_players(), game_days[1])

  expect_equal(
    pull(table_sum_data_prep(capped_tbl, capped_base, game_days[1], 2), games_remaining, player_team),
    c(Us = 4)
  )
})

test_that("a day under the lineup-spot cap keeps its own count", {
  # The cap is a ceiling per day, not a flat spots x days total: Ann plays on
  # two of the three days, so three spots still leaves two games.
  solo <- list(fake_player(1, "Ann", "LAL", "Us", c(1, 0, 1)))
  solo_base <- fake_h2h_base(solo, game_days[1:3])
  solo_tbl <- table_data_prep(solo_base, NULL, no_grey_players(), game_days[1])

  expect_equal(
    pull(table_sum_data_prep(solo_tbl, solo_base, game_days[1], 3), games_remaining, player_team),
    c(Us = 2)
  )
})

test_that("past daily totals are capped at the lineup spots", {
  days <- cur_date - 2:1
  capped_roster <- list(
    fake_player(1, "Ann", "LAL", "Us", c(1, 1)),
    fake_player(2, "Bob", "BOS", "Us", c(1, 1)),
    fake_player(3, "Cyd", "NYK", "Us", c(1, 1))
  )
  capped_base <- fake_h2h_base(capped_roster, days)
  capped_tbl <- table_data_prep(capped_base, NULL, no_grey_players(), days[1])

  sums <- table_sum_data_prep(capped_tbl, capped_base, days[1], 2)

  labels <- format(days, "%a (%d/%m)")
  expect_equal(unname(unlist(select(sums, all_of(labels)))), c(2, 2))
})

test_that("a benched past game is left out of the team total", {
  days <- cur_date - 2:1
  bench_roster <- list(
    fake_player(1, "Ann", "LAL", "Us", c(1, 1)),
    fake_player(2, "Bob", "BOS", "Us", c(1, 1), slot = "BE")
  )
  bench_base <- fake_h2h_base(bench_roster, days)
  bench_tbl <- table_data_prep(bench_base, NULL, no_grey_players(), days[1])

  sums <- table_sum_data_prep(bench_tbl, bench_base, days[1], 10)

  labels <- format(days, "%a (%d/%m)")
  expect_equal(unname(unlist(select(sums, all_of(labels)))), c(1, 1))
})

test_that("future daily totals can exceed the lineup spots", {
  days <- cur_date + 0:1
  over_roster <- list(
    fake_player(1, "Ann", "LAL", "Us", c(1, 1)),
    fake_player(2, "Bob", "BOS", "Us", c(1, 1)),
    fake_player(3, "Cyd", "NYK", "Us", c(1, 1))
  )
  over_base <- fake_h2h_base(over_roster, days)
  over_tbl <- table_data_prep(over_base, NULL, no_grey_players(), days[1])

  sums <- table_sum_data_prep(over_tbl, over_base, days[1], 2)

  labels <- format(days, "%a (%d/%m)")
  expect_equal(unname(unlist(select(sums, all_of(labels)))), c(3, 3))
})
