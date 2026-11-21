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

details_depth <- function() {
  list(
    LAL = tibble(
      team_abbreviation = "LAL",
      game_date = as.Date("2026-11-24"),
      opponent = "BOS",
      home = TRUE,
      position_group = c("G", "G", "G", "F", "F", "C"),
      player_id = 1:6,
      player_name = c("Ann", "Bob", "Dee", "Eve", "Fay", "Cyd"),
      expected_minutes = c(30, 12, 25, 20, 8, 28)
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

  html <- render_details(
    "Ann",
    "LAL",
    1L,
    "7",
    c("pts", "ast"),
    details_weights(),
    TRUE,
    depth = details_depth()
  )

  expect_match(html, "Ann Game Log", fixed = TRUE)
  expect_match(html, "LAL Last 7 Day Injury History", fixed = TRUE)
  expect_match(html, "LAL Depth Chart", fixed = TRUE)
  expect_match(html, "Ann, Bob", fixed = TRUE)
  expect_match(html, "fty_pts", fixed = TRUE)
})

test_that("an expanded row falls back to text when a player or injury list is missing", {
  local_pkg_data(ls_player_game_log = list(), ls_injuries = list("7" = list()))

  html <- render_details(
    NA_character_,
    "LAL",
    NA_integer_,
    "7",
    "pts",
    details_weights(),
    FALSE,
    depth = details_depth()
  )

  expect_match(html, "Player not found...", fixed = TRUE)
  expect_match(html, "No Injuries", fixed = TRUE)
})

test_that("expanded row tabs carry the Bootstrap 5 nav classes", {
  local_pkg_data(
    ls_player_game_log = list("1" = details_game_log()),
    ls_injuries = details_injuries()
  )

  old_theme <- shiny::shinyOptions()[["bootstrapTheme"]]
  shiny::shinyOptions(bootstrapTheme = bslib::bs_theme(version = 5))
  on.exit(shiny::shinyOptions(bootstrapTheme = old_theme), add = TRUE)

  tabs <- comparison_details_tabs(
    "Ann",
    "LAL",
    1L,
    "7",
    c("pts", "ast"),
    details_weights(),
    TRUE,
    depth = details_depth()
  )
  links <- tabs$children[[1]]$children[[1]]$children

  expect_length(links, 3)
  expect_match(links[[1]]$children[[1]]$attribs$class, "nav-link active", fixed = TRUE)
  expect_match(links[[2]]$children[[1]]$attribs$class, "nav-link", fixed = TRUE)
  expect_match(links[[3]]$children[[1]]$attribs$class, "nav-link", fixed = TRUE)
  expect_match(as.character(links[[3]]$children[[1]]), "Depth Chart", fixed = TRUE)
})

test_that("the depth chart lists every position and ranks by expected minutes", {
  html <- htmltools::renderTags(team_depth_chart(2L, "LAL", details_depth()))$html

  expect_match(html, "LAL Depth Chart", fixed = TRUE)
  expect_match(html, " - vs BOS", fixed = TRUE)
  expect_match(html, "font-size: 70%", fixed = TRUE)
  expect_false(stringr::str_detect(html, "Depth Chart \\("))
  expect_match(html, "max-width: 900px", fixed = TRUE)
  expect_equal(stringr::str_count(html, "border: 1px solid #e6e6e6"), 10)

  for (position in c("G", "F", "C")) {
    expect_match(html, position, fixed = TRUE)
  }

  expect_lt(stringr::str_locate(html, "Ann")[1], stringr::str_locate(html, "Bob")[1])
  expect_match(html, "30.0 min", fixed = TRUE)
  expect_match(html, "28.0 min", fixed = TRUE)
  expect_equal(stringr::str_count(html, "background-color: #f1e78e"), 1)
  expect_match(html, "background-color: #f1e78e[\\s\\S]*?Bob", perl = TRUE)
})

test_that("the depth chart falls back to text for an unknown team", {
  html <- htmltools::renderTags(team_depth_chart(1L, "XYZ", details_depth()))$html

  expect_match(html, "No depth chart available for this team.", fixed = TRUE)
})

test_that("an away depth chart marks the opponent as away", {
  depth <- details_depth()
  depth$LAL$home <- FALSE
  depth$LAL$opponent <- "NYK"

  html <- htmltools::renderTags(team_depth_chart(1L, "LAL", depth))$html

  expect_match(html, " - @ NYK", fixed = TRUE)
})
