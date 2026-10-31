# Package-data consistency: for a points league, each competitor's standings
# points total is the sum of their weighted category points from the drill-down.
# Both sides trace back to ESPN's own score (fty.matchup_result), so they must
# agree once the season has been built.

test_that("a points league's standings reconcile with its weighted category totals", {
  pkg <- as.environment("package:league")
  needed <- c("dfs_fty_standings", "dfs_fty_standings_cats")
  skip_if_not(rlang::env_has(pkg, needed), "package data not built")

  standings_all <- pkg[["dfs_fty_standings"]]
  cats_all <- pkg[["dfs_fty_standings_cats"]]

  points_leagues <- keep(names(standings_all), \(lg) "points_for" %in% names(standings_all[[lg]]))
  skip_if(length(points_leagues) == 0, "no points-league standings to reconcile")

  for (lg in points_leagues) {
    reconcile <- cats_all[[lg]] |>
      summarise(total = sum(fantasy_points, na.rm = TRUE), .by = competitor_id) |>
      inner_join(
        select(standings_all[[lg]], competitor_id, points_for),
        by = join_by(competitor_id)
      )

    expect_equal(reconcile$total, reconcile$points_for, tolerance = 0.01)
  }
})

test_that("player comparison has one row per player", {
  pkg <- as.environment("package:league")
  skip_if_not(rlang::env_has(pkg, "dfs_player_comparison"), "package data not built")

  duplicate_counts <- pkg[["dfs_player_comparison"]] |>
    purrr::map(\(windows) {
      purrr::map_int(windows, \(df) sum(duplicated(df$player_id)))
    }) |>
    unlist(use.names = FALSE)

  expect_true(all(duplicate_counts == 0L))
})

test_that("player comparison includes every scored league category", {
  pkg <- as.environment("package:league")
  needed <- c("dfs_player_comparison", "ls_lo_lg_cats")
  skip_if_not(all(rlang::env_has(pkg, needed)), "package data not built")

  comparisons <- pkg[["dfs_player_comparison"]]
  cats_all <- pkg[["ls_lo_lg_cats"]]

  for (lg in names(comparisons)) {
    available <- names(comparisons[[lg]][["7"]])
    requested <- c(
      unname(cats_all[[lg]][["Categories"]]),
      unname(cats_all[[lg]][["Z Scores"]])
    ) |>
      purrr::discard(\(x) stringr::str_like(x, "%_pct"))

    expect_length(setdiff(requested, available), 0)
  }
})

test_that("player game logs only contain completed games from the last 30 days", {
  pkg <- as.environment("package:league")
  needed <- c("ls_player_game_log", "cur_date")
  skip_if_not(all(rlang::env_has(pkg, needed)), "package data not built")

  game_dates <- pkg[["ls_player_game_log"]] |>
    purrr::map(\(df) df$game_date) |>
    unlist()

  skip_if(length(game_dates) == 0, "no games in the log window")

  expect_true(all(game_dates < pkg[["cur_date"]]))
  expect_true(all(game_dates >= pkg[["cur_date"]] - 30))
})

test_that("every built league has free-agent future games", {
  pkg <- as.environment("package:league")
  skip_if_not(rlang::env_has(pkg, "dfs_h2h_future"), "package data not built")

  future <- pkg[["dfs_h2h_future"]]
  for (lg in names(future)) {
    windows <- purrr::pluck(future, lg, "free_agent", "free_agent")
    expected <- c("7", "15", "30")
    expect_type(windows, "list")
    expect_true(all(expected %in% names(windows)))
    for (window in expected) {
      expect_gt(nrow(windows[[window]]), 0)
      expect_true(all(windows[[window]]$matchup_start <= windows[[window]]$matchup_end))
    }
  }
})
