# points_data_prep() weights the rolling-median player-game values by the
# league's category weights and sums them per competitor. Negative weights stay
# signed (Ejections), players listed Out contribute nothing, and a league that
# scores by category (weights all NA) yields no rows.

points_weights <- function(points = c(1, 2, -2, -5)) {
  tibble(
    nba_category = c("pts", "ast", "tov", "ej"),
    fmt_category = c("Points", "Assists", "Turnovers", "Ejections"),
    display_order = c(3, 7, 11, 15),
    points = points
  )
}

points_fixture <- function() {
  tibble(
    competitor = c("Me", "Me", "Rival"),
    inj_status = c(NA, "Out", NA),
    pts = c(30, 10, 7),
    ast = c(6, 3, 1),
    tov = c(3, 1, 2),
    ej = c(1, 0, 0)
  )
}

test_that("weighted values are summed per competitor and stay signed", {
  out <- points_data_prep(points_fixture(), points_weights())

  me <- filter(out, competitor == "Me")
  expect_equal(pull(me, value, name)[["pts"]], 30)
  expect_equal(pull(me, points, name)[["pts"]], 30)
  expect_equal(pull(me, points, name)[["ast"]], 12)
  expect_equal(pull(me, points, name)[["tov"]], -6)
  expect_equal(pull(me, points, name)[["ej"]], -5)

  rival <- filter(out, competitor == "Rival")
  expect_equal(pull(rival, points, name)[["tov"]], -4)
  expect_equal(pull(rival, points, name)[["ej"]], 0)
})

test_that("a player listed Out contributes nothing", {
  me <- filter(points_data_prep(points_fixture(), points_weights()), competitor == "Me")

  # The Out row's 10 pts, 3 ast, 1 tov and 0 ej are zeroed.
  expect_equal(pull(me, value, name)[["pts"]], 30)
  expect_equal(pull(me, points, name)[["ast"]], 12)
  expect_equal(pull(me, points, name)[["tov"]], -6)
})

test_that("categories are ordered by display order", {
  out <- filter(points_data_prep(points_fixture(), points_weights()), competitor == "Me")

  expect_equal(out$name, c("pts", "ast", "tov", "ej"))
})

test_that("a league that scores by category yields no rows", {
  weights <- points_weights(points = NA_real_)
  out <- points_data_prep(points_fixture(), weights)

  expect_equal(nrow(out), 0)
})

test_that("categories the frame does not carry are skipped", {
  weights <- points_weights() |>
    bind_rows(tibble(nba_category = "stl", fmt_category = "Steals", display_order = 8, points = 4))
  out <- points_data_prep(points_fixture(), weights)

  expect_false("stl" %in% out$name)
  expect_equal(nrow(out), 8)
})
