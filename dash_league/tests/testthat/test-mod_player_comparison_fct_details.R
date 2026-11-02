details_game_log <- function() {
  tibble(
    game_date = as.Date(c("2026-10-30", "2026-11-01")),
    opponent = c("BOS", "NYK"),
    min = c(30, 25),
    pts = c(20, 10),
    ast = c(5, 2),
    tov = c(1, 3)
  )
}

details_injuries <- function() {
  list(
    "7" = list(
      LAL = tibble(
        team = c("LAL", "LAL"),
        opponent = c("BOS", "NYK"),
        game_date = as.Date(c("2026-11-01", "2026-10-30")),
        player_names = c("Ann, Bob", "Cyd")
      )
    )
  )
}

details_weights <- function() {
  tibble(
    league_id = 1L,
    nba_category = c("pts", "ast", "tov"),
    fmt_category = c("Points", "Assists", "Turnovers"),
    display_order = c(3, 7, 11),
    points = c(1, 2, -2)
  )
}

render_details <- function(...) {
  htmltools::renderTags(comparison_details_tabs(...))$html
}

test_that("game logs carry fantasy points only in points leagues", {
  local_pkg_data(ls_player_game_log = list("1" = details_game_log()))

  points <- player_game_log_data(1L, c("pts", "ast"), details_weights(), is_points_league = TRUE)
  expect_equal(names(points), c("game_date", "opponent", "fty_pts", "min", "pts", "ast"))
  expect_equal(points$fty_pts, c(28, 8))

  category <- player_game_log_data(1L, c("pts", "ast"), details_weights(), is_points_league = FALSE)
  expect_equal(names(category), c("game_date", "opponent", "min", "pts", "ast"))
})

test_that("game logs are empty for a player with no games", {
  local_pkg_data(ls_player_game_log = list())

  expect_equal(nrow(player_game_log_data(99L, "pts", details_weights(), FALSE)), 0)
})

test_that("injury history is keyed by window and team", {
  local_pkg_data(ls_injuries = details_injuries())

  expect_equal(nrow(team_injury_data("7", "LAL")), 2)
  expect_equal(nrow(team_injury_data("15", "LAL")), 0)
  expect_equal(nrow(team_injury_data("7", "BOS")), 0)
})

test_that("an expanded row shows the game log and injuries side by side in tabs", {
  local_pkg_data(
    ls_player_game_log = list("1" = details_game_log()),
    ls_injuries = details_injuries()
  )

  html <- render_details("Ann", "LAL", 1L, "7", c("pts", "ast"), details_weights(), TRUE)

  expect_match(html, "Ann Game Log", fixed = TRUE)
  expect_match(html, "LAL Last 7 Day Injury History", fixed = TRUE)
  expect_match(html, "Ann, Bob", fixed = TRUE)
  expect_match(html, "fty_pts", fixed = TRUE)
})

test_that("an expanded row falls back to text when a player or injury list is missing", {
  local_pkg_data(ls_player_game_log = list(), ls_injuries = list("7" = list()))

  html <- render_details(NA_character_, "LAL", NA_integer_, "7", "pts", details_weights(), FALSE)

  expect_match(html, "Player not found...", fixed = TRUE)
  expect_match(html, "No Injuries", fixed = TRUE)
})
