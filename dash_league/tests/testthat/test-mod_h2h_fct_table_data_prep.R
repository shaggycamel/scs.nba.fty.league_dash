game_days <- cur_date + 0:3
roster <- h2h_test_roster()

test_that("every day of the matchup gets a column, in date order", {
  # The matchup's own days, plus the two after it that the tables carry.
  tbl <- table_data_prep(fake_h2h_base(roster, game_days), NULL, no_grey_players(), game_days[1])

  expect_equal(str_subset(names(tbl), "/"), format(cur_date + 0:5, "%a (%d/%m)"))
})

test_that("games_remaining counts the days from the pin onward", {
  df_base <- fake_h2h_base(roster, game_days)
  remaining <- \(pin) pull(table_data_prep(df_base, NULL, no_grey_players(), pin), games_remaining, player_name)

  expect_equal(remaining(game_days[1]), c(Ann = 3, Bob = 3, Cyd = 2))
  expect_equal(remaining(game_days[2]), c(Ann = 2, Bob = 2, Cyd = 2))
  expect_equal(remaining(game_days[3]), c(Ann = 2, Bob = 1, Cyd = 1))
  expect_equal(remaining(game_days[4]), c(Ann = 1, Bob = 1, Cyd = 0))
})

test_that("a pin between game days counts from the next one", {
  # pin_date need not land on a game day: Ann plays today and in three days,
  # and pinning tomorrow leaves just the later game.
  solo <- list(fake_player(1, "Ann", "LAL", "Us", c(1, 1)))
  df_base <- fake_h2h_base(solo, cur_date + c(0, 3))
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), cur_date + 1)

  expect_equal(pull(tbl, games_remaining, player_name), c(Ann = 1))
})

test_that("games for players listed Out still count", {
  # Out tags every one of Bob's cells with a trailing "*". Stripping it before
  # as.numeric() is what keeps those games in the total.
  df_base <- fake_h2h_base(roster, game_days)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), game_days[1])
  bob <- filter(tbl, player_name == "Bob")

  expect_true(all(str_detect(unlist(select(bob, all_of(format(game_days, "%a (%d/%m)")))), "\\*")))
  expect_equal(bob$games_remaining, 3)
  expect_no_warning(table_data_prep(df_base, NULL, no_grey_players(), game_days[1]))
})

test_that("a pin past the last game day leaves no games remaining", {
  # pin_date can outrun df_base for one reactive flush while the date picker
  # catches up with a newly selected matchup. It must match no columns rather
  # than index past the end of the frame.
  df_base <- fake_h2h_base(roster, game_days)

  expect_no_error(tbl <- table_data_prep(df_base, NULL, no_grey_players(), cur_date + 30))
  expect_equal(tbl$games_remaining, c(0, 0, 0))
})

test_that("a finished matchup leaves no games remaining", {
  past_days <- cur_date - 4:1
  tbl <- table_data_prep(fake_h2h_base(roster, past_days), NULL, no_grey_players(), past_days[1])

  expect_equal(tbl$games_remaining, c(0, 0, 0))
})

test_that("games_remaining sits ahead of the post-matchup days", {
  df_base <- fake_h2h_base(
    roster,
    game_days,
    matchup_end = cur_date + 1,
    matchup_end_plus = cur_date + 3
  )
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), game_days[1])

  expect_equal(
    names(tbl)[which(names(tbl) == "games_remaining") + 1:2],
    format(cur_date + 2:3, "%a (%d/%m)")
  )
})

test_that("games_remaining stops at matchup_end and ignores the post-matchup days", {
  # The column is placed ahead of the two post-matchup days, so the total must
  # not span them. Ann has one game left before matchup_end, not three.
  df_base <- fake_h2h_base(
    roster,
    game_days,
    matchup_end = cur_date + 1,
    matchup_end_plus = cur_date + 3
  )
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), game_days[1])

  expect_equal(pull(tbl, games_remaining, player_name), c(Ann = 1, Bob = 2, Cyd = 1))
})

test_that("a matchup spanning new year resolves its columns correctly", {
  # Column labels carry no year, so the December and January columns are only
  # distinguishable via game_date.
  new_year_days <- as.Date(c("2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"))
  df_base <- fake_h2h_base(roster, new_year_days, matchup_end = max(new_year_days))
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), as.Date("2027-01-01"))

  expect_equal(str_subset(names(tbl), "/"), format(new_year_days[1] + 0:5, "%a (%d/%m)"))
  # Ann plays on 1 Jan and 2 Jan; a year-blind lookup would drop both.
  expect_equal(pull(tbl, games_remaining, player_name), c(Ann = 2, Bob = 1, Cyd = 1))
})

test_that("days with no games get a column of their own", {
  # Ann plays today and in three days; the two days between have no games at all
  # and would otherwise be missing from the table entirely.
  solo <- list(fake_player(1, "Ann", "LAL", "Us", c(1, 1)))
  df_base <- fake_h2h_base(solo, cur_date + c(0, 3))
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), cur_date)

  expect_equal(str_subset(names(tbl), "/"), format(cur_date + 0:5, "%a (%d/%m)"))
  expect_equal(unname(unlist(select(tbl, contains("/")))), c("1", "0", "0", "1", "0", "0"))
  expect_equal(tbl$games_remaining, 2)
})

test_that("the final matchup lays out no post-matchup days", {
  # Week 19, the last before Post Fantasy, has no following matchup to look
  # ahead to. With post_matchup_days = 0 the two trailing columns are dropped.
  days <- cur_date + 0:1
  df_base <- fake_h2h_base(roster, days, matchup_end = days[2])
  default <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  final <- table_data_prep(df_base, NULL, no_grey_players(), days[1], post_matchup_days = 0)

  expect_equal(str_subset(names(default), "/"), format(cur_date + 0:3, "%a (%d/%m)"))
  expect_equal(str_subset(names(final), "/"), format(days, "%a (%d/%m)"))
})

test_that("postseason roster uses the latest assignment snapshot for one competitor", {
  assignments <- tibble(
    competitor_id = c(1L, 1L, 1L, 2L),
    assigned_date = as.Date(c("2026-03-01", "2026-03-08", "2026-03-08", "2026-03-15")),
    player_id = c(10L, 10L, 11L, 20L),
    player_name = c("Ann", "Ann", "Bob", "Cyd"),
    player_team = c("LAL", "LAL", "BOS", "NYK")
  )

  roster <- postseason_roster_data_prep(assignments, 1L)

  expect_named(roster, c("player_id", "player_name", "player_team"))
  expect_equal(roster$player_name, c("Ann", "Bob"))
  expect_equal(roster$player_team, c("LAL", "BOS"))
})
