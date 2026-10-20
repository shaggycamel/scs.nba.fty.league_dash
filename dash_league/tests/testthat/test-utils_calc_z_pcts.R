# calc_z_pcts() reads made/attempted counts and returns shooting percentages
# plus z-scores for the field-goal and free-throw impact of each row. The
# league average it draws from is the total made over the total attempted, so it
# weights volume the same way the fantasy scoring does.

z_pcts_fixture <- function() {
  tibble(
    player = c("A", "B", "C"),
    fgm = c(10, 2, 0),
    fga = c(10, 10, 0),
    ftm = c(4, 1, 0),
    fta = c(8, 8, 0)
  )
}

test_that("made over attempted gives the shooting percentages", {
  out <- calc_z_pcts(z_pcts_fixture())

  # B has 2/10, and C took nothing so coalesce turns 0/0 into 0.
  expect_equal(out$fg_pct, c(1, 0.2, 0))
  expect_equal(out$ft_pct, c(0.5, 0.125, 0))
})

test_that("impact columns are dropped once the z-scores are derived", {
  out <- calc_z_pcts(z_pcts_fixture())

  expect_false(any(str_detect(names(out), "impact")))
  expect_true(all(c("fg_z", "ft_z") %in% names(out)))
})

test_that("z-scores standardise each row's impact against the league", {
  out <- calc_z_pcts(z_pcts_fixture())

  # League fg is 12/20 = 0.6, so the per-row impacts are 4, -4 and 0: a mean of
  # zero and a standard deviation of 4. The free throws work out the same at 1.5.
  expect_equal(out$fg_z, c(1, -1, 0))
  expect_equal(out$ft_z, c(1, -1, 0))
})

test_that("a zero-attempt row is not an error", {
  expect_no_error(calc_z_pcts(z_pcts_fixture()))
  expect_no_warning(z_pcts_fixture() |> calc_z_pcts())
})

test_that("an empty frame keeps the expected columns", {
  out <- calc_z_pcts(tibble(
    player = character(),
    fgm = numeric(),
    fga = numeric(),
    ftm = numeric(),
    fta = numeric()
  ))

  expect_equal(nrow(out), 0L)
  expect_true(all(c("fg_pct", "ft_pct", "fg_z", "ft_z") %in% names(out)))
})

test_that("missing shooting columns are added as zero", {
  out <- calc_z_pcts(tibble(player = "A", pts = 10))

  expect_equal(out$fgm, 0)
  expect_equal(out$fga, 0)
  expect_equal(out$ftm, 0)
  expect_equal(out$fta, 0)
  expect_equal(out$fg_pct, 0)
  expect_true(all(c("fg_z", "ft_z") %in% names(out)))
})
