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
