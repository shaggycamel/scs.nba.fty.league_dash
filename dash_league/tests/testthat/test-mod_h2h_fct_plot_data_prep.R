# plot_data_prep() reshapes a matchup's box-score rows into the long frame the
# plotly charts read: one row per competitor per stat. Percentages are built
# from the made/attempted totals, and players listed Out contribute nothing.

plot_fixture <- function() {
  tibble(
    competitor = c("Me", "Me", "Rival"),
    player_id = c(1L, 2L, 3L),
    player_name = c("A", "B", "C"),
    inj_status = c(NA, "Out", NA),
    game_date = as.Date("2026-01-02"),
    matchup_start = as.Date("2025-12-29"),
    matchup_end = as.Date("2026-01-04"),
    fgm = c(10, 4, 2),
    fga = c(20, 8, 5),
    ftm = c(5, 2, 1),
    fta = c(10, 4, 2),
    pts = c(30, 10, 7),
    ast = c(6, 3, 1),
    tov = c(3, 1, 2)
  )
}

plot_categories <- function() {
  list("1" = list(Categories = c("pts" = "pts", "ast" = "ast")))
}

plot_prep <- function(df, league_id = 1) {
  local_pkg_data(ls_lo_lg_cats = plot_categories())
  plot_data_prep(df, list(league_id = league_id))
}

points_categories <- function() {
  list("1" = list(Categories = c("pts" = "pts", "ast" = "ast", "tov" = "tov")))
}

points_weights <- function() {
  tibble(
    league_id = 1L,
    nba_category = c("pts", "ast", "tov"),
    fmt_category = c("Points", "Assists", "Turnovers"),
    display_order = c(3, 7, 11),
    points = c(1, 2, -2)
  )
}

points_prep <- function(df) {
  local_pkg_data(
    ls_lo_lg_cats = points_categories(),
    df_fty_cat_weights = points_weights()
  )
  plot_data_prep(df, list(league_id = 1))
}

test_that("shooting percentages are built from made and attempted totals", {
  out <- plot_prep(plot_fixture())
  me <- filter(out, competitor == "Me")

  expect_equal(pull(me, value, name)[["fg_pct"]], 0.5)
  expect_equal(pull(me, value, name)[["ft_pct"]], 0.5)
  expect_equal(
    pull(filter(out, competitor == "Rival"), value, name)[["fg_pct"]],
    0.4
  )
  expect_match(pull(me, label, name)[["fg_pct"]], "Total: 10/20 (50.00%)", fixed = TRUE)
  expect_match(pull(me, label, name)[["fg_pct"]], "A: 10/20", fixed = TRUE)
})

test_that("a player listed Out contributes nothing to the totals", {
  me <- filter(plot_prep(plot_fixture()), competitor == "Me")

  # B's 10 points and 3 assists are zeroed, leaving A's 30 and 6.
  expect_equal(pull(me, value, name)[["pts"]], 30)
  expect_equal(pull(me, value, name)[["ast"]], 6)
  expect_match(pull(me, label, name)[["pts"]], "Total: 30", fixed = TRUE)
})

test_that("games after the matchup end do not reach the plot", {
  df <- plot_fixture()
  lookahead <- df |>
    slice(1) |>
    mutate(game_date = matchup_end + 1, pts = 100)
  lookahead_only <- df |>
    slice(1) |>
    mutate(
      player_id = 4L,
      player_name = "D",
      game_date = matchup_end + 1,
      pts = 99
    )

  out <- plot_prep(bind_rows(df, lookahead, lookahead_only))
  me <- filter(out, competitor == "Me")

  expect_equal(pull(me, value, name)[["pts"]], 30)
  expect_false(any(str_detect(me$label, "D: ")))
})

test_that("excluded rows do not reach the plot", {
  df <- plot_fixture() |>
    mutate(
      excluded = player_id == 1L,
      inj_status = NA_character_
    )

  out <- plot_prep(df)
  me <- filter(out, competitor == "Me")

  expect_equal(pull(me, value, name)[["pts"]], 10)
  expect_false(any(str_detect(me$label, "A: ")))
})

test_that("each competitor's categories are ordered with percentages last", {
  out <- plot_prep(plot_fixture())

  expect_equal(as.character(filter(out, competitor == "Me")$name), c("ast", "pts", "fg_pct", "ft_pct"))
  expect_equal(as.character(filter(out, competitor == "Rival")$name), c("ast", "pts", "fg_pct", "ft_pct"))
})

test_that("points leagues start with an overall fty-points row", {
  out <- points_prep(plot_fixture())
  me <- filter(out, competitor == "Me")

  expect_equal(as.character(me$name), c("FTY Pts", "pts", "ast", "tov"))
  expect_equal(pull(me, value, name)[["FTY Pts"]], 36)
  expect_true(me$is_overall[1])
  expect_false(any(me$is_overall[-1]))
  expect_match(pull(me, label, name)[["FTY Pts"]], "Total: 36", fixed = TRUE)
  expect_match(pull(me, label, name)[["FTY Pts"]], "A: 36", fixed = TRUE)
})

test_that("weighted category rows keep their signs", {
  out <- points_prep(plot_fixture())
  tov <- filter(out, competitor == "Me", as.character(name) == "tov")

  expect_equal(tov$value, -6)
  expect_match(tov$label, "Total: -6", fixed = TRUE)
})

test_that("post-matchup games are excluded from FTY points", {
  df <- plot_fixture() |>
    filter(competitor == "Me")
  df <- bind_rows(
    df,
    df |>
      slice(1) |>
      mutate(game_date = matchup_end + 1, pts = 100)
  )

  out <- points_prep(df)
  me <- filter(out, competitor == "Me")

  expect_equal(pull(me, value, name)[["FTY Pts"]], 36)
})

test_that("postseason plot data combines completed matchups for one competitor", {
  matchup_one <- list(
    "1" = tibble(
      player_id = c(10L, 10L),
      game_date = as.Date(c("2026-03-01", "2026-03-10")),
      matchup_end = as.Date(c("2026-03-07", "2026-03-07")),
      pts = c(12, 20)
    ),
    "2" = tibble(
      player_id = 20L,
      game_date = as.Date("2026-03-02"),
      matchup_end = as.Date("2026-03-07"),
      pts = 9
    )
  )
  matchup_two <- list(
    "1" = tibble(
      player_id = 10L,
      game_date = as.Date("2026-03-08"),
      matchup_end = as.Date("2026-03-14"),
      pts = 15
    )
  )

  postseason <- postseason_base_data_prep(
    list("1" = matchup_one, "2" = matchup_two),
    selected_competitor_id = 1L,
    competitor_name = "Us"
  )

  expect_equal(postseason$player_id, c(10L, 10L))
  expect_equal(postseason$pts, c(12, 15))
  expect_equal(postseason$competitor, c("Us", "Us"))
})
