test_that("stats are multiplied by their league weights", {
  df <- tibble(pts = c(10, 5), ast = c(5, 2), tov = c(2, 1))
  weights <- tibble(nba_category = c("pts", "ast", "tov"), points = c(1, 2, -2))

  expect_equal(calc_fty_points(df, weights), c(16, 7))
})

test_that("missing stats count as zero", {
  df <- tibble(pts = c(10, NA), ast = c(5, 2))
  weights <- tibble(nba_category = c("pts", "ast"), points = c(1, 2))

  expect_equal(calc_fty_points(df, weights), c(20, 4))
})

test_that("a league without weighted categories returns NA", {
  df <- tibble(pts = c(10, 5), ast = c(5, 2))
  weights <- tibble(nba_category = c("pts", "ast"), points = c(NA_real_, NA_real_))

  expect_equal(calc_fty_points(df, weights), c(NA_real_, NA_real_))
})

test_that("weights for absent columns are ignored", {
  df <- tibble(pts = c(10, 5))
  weights <- tibble(nba_category = c("pts", "blk"), points = c(1, 4))

  expect_equal(calc_fty_points(df, weights), c(10, 5))
})

test_that("an empty frame returns an empty vector", {
  df <- tibble(pts = numeric(), ast = numeric())
  weights <- tibble(nba_category = c("pts", "ast"), points = c(1, 2))

  expect_equal(calc_fty_points(df, weights), numeric())
})
