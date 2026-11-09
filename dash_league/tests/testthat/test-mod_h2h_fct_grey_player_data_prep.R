# grey_player_data_prep() works out which days a player should be greyed in the
# h2h table: the days before a stint on the roster, the gaps between stints, and
# the days after the last stint when the player was not re-added. It reads the
# roster from package data, so the tests mock that and drive it with a hand-built
# df_base.

grey_fixtures <- function() {
  start <- cur_date - 3

  df_base <- tibble(
    player_id = c(10L, 10L, 11L, 11L, 12L, 12L, 13L, 14L, 14L, 14L, 20L, 21L, 22L, 30L),
    competitor_id = c(1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 3L),
    game_date = as.Date(c(
      start,
      start + 1,
      start + 2,
      cur_date,
      start,
      cur_date,
      start + 1,
      start,
      start + 1,
      cur_date,
      start,
      start,
      start + 2,
      start
    )),
    tense = "past",
    matchup_start = start,
    matchup_end = cur_date + 3
  )

  roster <- tibble(
    competitor_id = c(
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      1L,
      2L,
      2L,
      2L,
      2L,
      2L,
      2L,
      3L
    ),
    matchup_period = c(
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      5L,
      6L,
      5L
    ),
    player_id = c(
      10L,
      10L,
      11L,
      11L,
      12L,
      12L,
      12L,
      12L,
      13L,
      13L,
      13L,
      14L,
      14L,
      14L,
      20L,
      20L,
      20L,
      22L,
      22L,
      21L,
      30L
    ),
    assigned_date = as.Date(c(
      start,
      start + 1,
      start + 2,
      cur_date,
      start,
      start + 1,
      start + 2,
      cur_date,
      start + 1,
      start + 2,
      cur_date,
      start,
      start + 1,
      cur_date,
      start,
      start + 2,
      cur_date,
      start + 2,
      cur_date,
      start,
      start
    ))
  ) |>
    mutate(matchup_start = start, matchup_end = cur_date + 3, lineup_slot = "PG")

  list(df_base = df_base, roster = roster)
}

grey_prep <- function(input, df_base, rv_carry_thru, opponent, rv_alter_team = list()) {
  local_pkg_data(dfs_fty_roster = list("1" = grey_fixtures()$roster))
  grey_player_data_prep(input, df_base, rv_carry_thru, opponent, rv_alter_team)
}

grey_opponent <- function() list(id = 2L, name = "Rival")

grey_rv <- function(cur_matchup_period = 5L) {
  list(
    league_id = 1,
    competitor_id = 1,
    cur_matchup_period = cur_matchup_period
  )
}

grey_intervals <- function(out, player_id, competitor_id = 1L) {
  out |>
    filter(player_id == !!player_id, competitor_id == !!competitor_id) |>
    pull(grey_intervals) |>
    pluck(1)
}

test_that("a player rostered throughout has no grey intervals", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_false(12L %in% out$player_id)
})

test_that("a player added mid-matchup is grey before they were added", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_equal(
    grey_intervals(out, 11L),
    tibble(start = cur_date - 3, end = cur_date - 2)
  )
})

test_that("a player dropped mid-matchup is grey after their last rostered day", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_equal(
    grey_intervals(out, 10L),
    tibble(start = cur_date - 1, end = as.Date("3000-01-01"))
  )
})

test_that("a player dropped and readded is grey only between stints", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_equal(
    grey_intervals(out, 14L),
    tibble(start = cur_date - 1, end = cur_date - 1)
  )
})

test_that("a still-rostered player with no recent game is not grey after it", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_equal(
    grey_intervals(out, 13L),
    tibble(start = cur_date - 3, end = cur_date - 3)
  )
})

test_that("a missing snapshot day does not split a stint", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_false(20L %in% out$player_id)
})

test_that("a bench day inside a stint is not treated as an absence", {
  roster <- grey_fixtures()$roster |>
    mutate(
      lineup_slot = if_else(player_id == 12L & assigned_date == cur_date - 2, "BE", lineup_slot)
    )
  local_pkg_data(dfs_fty_roster = list("1" = roster))

  out <- grey_player_data_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    list()
  )

  expect_false(12L %in% out$player_id)
})

test_that("grey intervals are built for the opponent as well", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_equal(
    grey_intervals(out, 22L, competitor_id = 2L),
    tibble(start = cur_date - 3, end = cur_date - 2)
  )
})

test_that("only the two opponents' current-matchup players are considered", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_false(any(c(30L, 21L) %in% out$player_id))
})

test_that("the result carries the player and competitor with their intervals", {
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    list(league_id = 1, competitor_id = 1),
    grey_opponent
  )

  expect_named(out, c("competitor_id", "player_id", "grey_intervals"))
})

test_that("a matchup with no roster history has no grey intervals", {
  expect_no_warning(
    out <- grey_prep(
      list(matchup = 7L),
      grey_fixtures()$df_base,
      list(league_id = 1, competitor_id = 1),
      grey_opponent
    )
  )

  expect_named(out, c("competitor_id", "player_id", "grey_intervals"))
  expect_equal(nrow(out), 0)
})

test_that("an alter-team exclusion greys from the action date to the end", {
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_equal(
    grey_intervals(out, 12L),
    tibble(start = cur_date, end = as.Date("3000-01-01"))
  )
})

test_that("an exclusion greys on after the action date even with no games left", {
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date + 3)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_equal(
    grey_intervals(out, 12L),
    tibble(start = cur_date + 3, end = as.Date("3000-01-01"))
  )
})

test_that("an exclusion from an earlier matchup starts at the later matchup", {
  later <- grey_fixtures()$df_base |>
    mutate(
      matchup_start = cur_date + 7,
      matchup_end = cur_date + 13
    )
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 6L),
    later,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_equal(
    grey_intervals(out, 12L),
    tibble(start = cur_date + 7, end = as.Date("3000-01-01"))
  )
})

test_that("an alter exclusion combines with the player's roster intervals", {
  ex <- list(list(
    action = "ex",
    player_id = 11L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_equal(
    grey_intervals(out, 11L),
    tibble(
      start = c(cur_date - 3, cur_date),
      end = c(cur_date - 2, as.Date("3000-01-01"))
    )
  )
})

test_that("an add wins over an exclusion for the same player", {
  moves <- list(
    list(
      action = "ex",
      player_id = 12L,
      action_date = as.character(cur_date)
    ),
    list(
      action = "add",
      player_id = 12L,
      action_date = as.character(cur_date)
    )
  )
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    moves
  )

  expect_false(12L %in% out$player_id)
})

test_that("an alter exclusion applies without roster history", {
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 7L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_equal(
    grey_intervals(out, 12L),
    tibble(start = cur_date, end = as.Date("3000-01-01"))
  )
})

test_that("an exclusion dated before today is ignored", {
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date - 1)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_false(12L %in% out$player_id)
})

test_that("an exclusion only applies from the current matchup onward", {
  ex <- list(list(
    action = "ex",
    player_id = 12L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 4L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    ex
  )

  expect_false(12L %in% out$player_id)
})

test_that("a free agent added via alter team is grey before the add date", {
  added_base <- grey_fixtures()$df_base |>
    tibble::add_row(
      player_id = 99L,
      competitor_id = 1L,
      game_date = cur_date,
      tense = "future",
      matchup_start = cur_date - 3,
      matchup_end = cur_date + 3
    )
  add <- list(list(
    action = "add",
    player_id = 99L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    added_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_equal(
    grey_intervals(out, 99L),
    tibble(start = cur_date - 3, end = cur_date - 1)
  )
})

test_that("an add ends an earlier absence on the day before the add", {
  add <- list(list(
    action = "add",
    player_id = 10L,
    action_date = as.character(cur_date + 2)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_equal(
    grey_intervals(out, 10L),
    tibble(start = cur_date - 1, end = cur_date + 1)
  )
})

test_that("an add leaves a genuinely rostered stretch unshaded", {
  add <- list(list(
    action = "add",
    player_id = 12L,
    action_date = as.character(cur_date + 2)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_false(12L %in% out$player_id)
})

test_that("an add dated before today is ignored", {
  added_base <- grey_fixtures()$df_base |>
    tibble::add_row(
      player_id = 99L,
      competitor_id = 1L,
      game_date = cur_date,
      tense = "future",
      matchup_start = cur_date - 3,
      matchup_end = cur_date + 3
    )
  add <- list(list(
    action = "add",
    player_id = 99L,
    action_date = as.character(cur_date - 1)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    added_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_false(99L %in% out$player_id)
})

test_that("an opponent's player is grey before the add for us and after it for them", {
  added_base <- grey_fixtures()$df_base |>
    tibble::add_row(
      player_id = 20L,
      competitor_id = 1L,
      game_date = cur_date,
      tense = "future",
      matchup_start = cur_date - 3,
      matchup_end = cur_date + 3
    )
  add <- list(list(
    action = "add",
    player_id = 20L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    added_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_equal(
    grey_intervals(out, 20L, competitor_id = 1L),
    tibble(start = cur_date - 3, end = cur_date - 1)
  )
  expect_equal(
    grey_intervals(out, 20L, competitor_id = 2L),
    tibble(start = cur_date, end = as.Date("3000-01-01"))
  )
})

test_that("a third team's add does not grey the displayed opponent", {
  add <- list(list(
    action = "add",
    player_id = 30L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 5L),
    grey_fixtures()$df_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_false(30L %in% filter(out, competitor_id == 2L)$player_id)
})

test_that("an add only greys from the current matchup onward", {
  added_base <- grey_fixtures()$df_base |>
    tibble::add_row(
      player_id = 99L,
      competitor_id = 1L,
      game_date = cur_date,
      tense = "future",
      matchup_start = cur_date - 3,
      matchup_end = cur_date + 3
    )
  add <- list(list(
    action = "add",
    player_id = 99L,
    action_date = as.character(cur_date)
  ))
  out <- grey_prep(
    list(matchup = 4L),
    added_base,
    grey_rv(),
    grey_opponent,
    add
  )

  expect_false(99L %in% out$player_id)
})
