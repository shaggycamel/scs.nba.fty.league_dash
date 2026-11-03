# The data pipeline (data-raw/_generate_all.R) reads nba/fty views that resolve
# player ids to names through the util player-matching layer
# (util.player_id_map_vw) and weights a points league's categories into its
# official score. These tests assert those contracts against the database. They
# need a live postgres instance and skip when one isn't reachable, mirroring
# test-utils_database.R.

pipeline_db <- function() {
  tryCatch(db_connect("postgres"), error = function(e) NULL)
}

latest_roster_season <- function(con) {
  DBI::dbGetQuery(con, "SELECT max(season) AS season FROM nba.team_roster_vw")$season
}

test_that("current-season nba roster players all resolve through util.player_id_map_vw", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  season <- latest_roster_season(con)
  skip_if(is.na(season), "no roster data available")

  res <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*)::int AS ids,
            count(*) FILTER (WHERE nm.player_key IS NULL)::int AS unmatched
       FROM (SELECT DISTINCT player_id FROM nba.team_roster_vw
              WHERE season = '%1$s' AND player_id IS NOT NULL) tr
       LEFT JOIN util.player_id_map_vw nm ON tr.player_id = nm.nba_id::FLOAT8",
    season))

  expect_gt(res$ids, 0L)
  expect_equal(res$unmatched, 0L)
})

test_that("current-season fty roster players bridge to nba ids via util.player_id_map_vw", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  season <- latest_roster_season(con)
  skip_if(is.na(season), "no roster data available")

  res <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*)::int AS ids,
            count(*) FILTER (WHERE nm.player_key IS NULL)::int AS unmatched
       FROM (SELECT DISTINCT player_id FROM fty.roster_schedule_vw
              WHERE season = '%1$s' AND player_id IS NOT NULL) r
       LEFT JOIN util.player_id_map_vw nm ON r.player_id = nm.nba_id::FLOAT8",
    season))

  expect_gt(res$ids, 0L)
  expect_equal(res$unmatched, 0L)
})

test_that("box score rows with a player_id always carry a conformed player_name", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  season <- latest_roster_season(con)
  skip_if(is.na(season), "no roster data available")

  bad <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*)::int AS n FROM nba.player_box_score_vw
      WHERE season = '%s' AND player_id IS NOT NULL AND player_name IS NULL",
    season))$n

  expect_equal(bad, 0L)
})

test_that("recent injury rows with an nba_id resolve through util.player_id_map_vw", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  bad <- DBI::dbGetQuery(con, "
    SELECT count(*)::int AS n
      FROM nba.injuries i
      LEFT JOIN util.player_id_map_vw nm ON i.nba_id = nm.nba_id
     WHERE i.status = 'Out'
       AND i.game_date >= (SELECT max(game_date) FROM nba.injuries) - INTERVAL '30 days'
       AND i.nba_id IS NOT NULL
       AND nm.player_key IS NULL")$n

  expect_equal(bad, 0L)
})

test_that("a points league's weighted categories reproduce ESPN's official matchup score", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  weighted <- DBI::dbGetQuery(con, "
    SELECT count(*)::int AS n
      FROM fty.matchup_box_score_vw
     WHERE scoring_type = 'H2H_POINTS' AND fantasy_points IS NOT NULL")$n
  skip_if(weighted == 0L, "no points-league matchup box scores available")

  mismatches <- DBI::dbGetQuery(con, "
    WITH weighted AS (
      SELECT season, platform, league_id, matchup, competitor_id,
             sum(fantasy_points) AS fantasy_points
        FROM fty.matchup_box_score_vw
       WHERE scoring_type = 'H2H_POINTS'
       GROUP BY 1, 2, 3, 4, 5
    )
    SELECT count(*)::int AS n
      FROM weighted w
      JOIN fty.matchup_result mr
        ON mr.season = w.season
       AND mr.platform = w.platform
       AND mr.league_id = w.league_id
       AND mr.matchup = w.matchup
       AND mr.competitor_id = w.competitor_id
     WHERE abs(w.fantasy_points - mr.score) > 0.001")$n

  expect_equal(mismatches, 0L)
})

test_that("a points league's h2h past totals reconcile with the official matchup score", {
  con <- pipeline_db()
  skip_if(is.null(con), "no local NBA database available")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  pkg <- as.environment("package:league")
  needed <- c("dfs_h2h_past", "df_fty_cat_weights", "df_fty_base", "cur_date")
  skip_if_not(all(rlang::env_has(pkg, needed)), "package data not built")

  season <- unique(pkg[["df_fty_base"]]$season)
  skip_if(length(season) != 1, "package data spans more than one season")

  weights <- dplyr::filter(pkg[["df_fty_cat_weights"]], !is.na(points))
  skip_if(nrow(weights) == 0, "no points league in the built leagues")

  # Only matchups whose roster snapshots all carry a slot can be expected to
  # match: the line-up was not captured before that date.
  covered <- DBI::dbGetQuery(con, sprintf(
    "SELECT min(assigned_date) AS first_date
       FROM fty.competitor_roster
      WHERE season = '%s' AND lineup_slot IS NOT NULL",
    season
  ))$first_date
  skip_if(is.na(covered), "no lineup slots captured for the built season yet")

  past <- flatten_h2h_past(pkg[["dfs_h2h_past"]]) |>
    dplyr::filter(
      !is.na(game_date),
      game_date <= matchup_end,
      matchup_start >= covered,
      # A live matchup's official score is still moving, and its later games
      # have no box score yet, so only a closed one can be compared.
      matchup_end < pkg[["cur_date"]]
    )
  skip_if(nrow(past) == 0, "no completed matchups inside the slot-covered window")

  cats <- unique(weights$nba_category)

  totals <- past |>
    dplyr::select(league_id, matchup_period, competitor_id, tidyselect::any_of(cats)) |>
    tidyr::pivot_longer(tidyselect::any_of(cats), names_to = "nba_category", values_to = "value") |>
    dplyr::inner_join(
      dplyr::select(weights, league_id, nba_category, points),
      by = dplyr::join_by(league_id, nba_category)
    ) |>
    dplyr::summarise(
      total = sum(value * points, na.rm = TRUE),
      .by = c(league_id, matchup_period, competitor_id)
    )

  official <- DBI::dbGetQuery(con, sprintf(
    "SELECT league_id::int AS league_id, matchup::int AS matchup,
            competitor_id::int AS competitor_id, score
       FROM fty.matchup_result
      WHERE season = '%s'",
    season
  ))

  reconciled <- dplyr::inner_join(
    totals,
    official,
    by = dplyr::join_by(league_id, matchup_period == matchup, competitor_id)
  )
  skip_if(nrow(reconciled) == 0, "no official scores for the slot-covered matchups")
  skip_if(all(reconciled$score <= 0), "no scored matchups inside the slot-covered window")

  # A daily snapshot can miss a line-up change made after the run, so this is a
  # near-match rather than an exact one; leaving a bench player in, by contrast,
  # overshoots by tens of percent.
  relative_error <- abs(reconciled$total - reconciled$score) / pmax(reconciled$score, 1)
  expect_lte(max(relative_error), 0.05)
})
