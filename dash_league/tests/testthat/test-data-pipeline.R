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
