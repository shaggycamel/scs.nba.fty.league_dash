test_that("standings_division_groups returns ordered groups", {
  df <- tibble(
    competitor_id = 1:4,
    division_id = c(1L, 0L, 1L, 0L),
    division_name = c("Group B", "Group A", "Group B", "Group A")
  )

  out <- standings_division_groups(df)

  expect_equal(out$division_id, c(0L, 1L))
  expect_equal(out$division_name, c("Group A", "Group B"))
})

test_that("standings_division_groups returns NULL without a full division split", {
  expect_null(standings_division_groups(tibble(competitor_id = 1:2)))
  expect_null(standings_division_groups(tibble(
    competitor_id = 1:2,
    division_id = NA_integer_,
    division_name = NA_character_
  )))
  expect_null(standings_division_groups(tibble(
    competitor_id = 1:2,
    division_id = c(0L, NA_integer_),
    division_name = c("Group A", NA_character_)
  )))
})
