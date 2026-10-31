# The colDef style callbacks take (value, index) and return a list of CSS
# properties, or NULL when the cell needs no special treatment.
cell_style <- function(col_fmt, col, value, index = 1) {
  col_fmt[[col]]$style(value, index)
}

pin_yellow <- list(background = "#f1e78e94")
alert_red <- list(background = "#ea7878ff")

test_that("the pinned day is highlighted", {
  days <- cur_date + 0:2
  df_base <- fake_h2h_base(h2h_test_roster(), days)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  col_dates <- col_dates_from_labels(names(tbl), min(df_base$matchup_start))
  labels <- format(days, "%a (%d/%m)")

  col_fmt <- game_tbl_col_fmt(tbl, days[2], max(days), col_dates)

  expect_equal(cell_style(col_fmt, labels[2], "1"), pin_yellow)
  expect_null(cell_style(col_fmt, labels[1], "1"))
  expect_null(cell_style(col_fmt, labels[3], "1"))
})

test_that("the pinned day is highlighted across new year", {
  # Parsing "Fri (01/01)" back into a date lands in the wrong year, which put the
  # highlight on the wrong column for any matchup week straddling new year.
  days <- as.Date(c("2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"))
  df_base <- fake_h2h_base(h2h_test_roster(), days)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  col_dates <- col_dates_from_labels(names(tbl), min(df_base$matchup_start))
  labels <- format(days, "%a (%d/%m)")

  col_fmt <- game_tbl_col_fmt(tbl, as.Date("2027-01-01"), max(days), col_dates)

  expect_equal(cell_style(col_fmt, labels[3], "1"), pin_yellow)
  expect_null(cell_style(col_fmt, labels[1], "1"))
  expect_null(cell_style(col_fmt, labels[2], "1"))
  expect_null(cell_style(col_fmt, labels[4], "1"))
})

test_that("days past the matchup end are shaded", {
  days <- cur_date + 0:3
  df_base <- fake_h2h_base(h2h_test_roster(), days, matchup_end = cur_date + 1)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  labels <- format(days, "%a (%d/%m)")

  col_fmt <- game_tbl_col_fmt(tbl, days[1], cur_date + 1, col_dates_from_labels(names(tbl), min(df_base$matchup_start)))

  expect_equal(cell_style(col_fmt, labels[3], "1"), list(background = "#eee5ff94"))
  expect_equal(cell_style(col_fmt, labels[4], "1"), list(background = "#eee5ff94"))
})

test_that("a cell is flagged when the player is out", {
  days <- cur_date + 0:2
  df_base <- fake_h2h_base(h2h_test_roster(), days)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  labels <- format(days, "%a (%d/%m)")

  col_fmt <- game_tbl_col_fmt(tbl, days[1], max(days), col_dates_from_labels(names(tbl), min(df_base$matchup_start)))

  expect_equal(cell_style(col_fmt, labels[2], "1*", index = 2), alert_red)
})

test_that("summary cells above the league's starter count are flagged", {
  days <- cur_date + 0:2
  df_base <- fake_h2h_base(h2h_test_roster(), days)
  tbl <- table_data_prep(df_base, NULL, no_grey_players(), days[1])
  labels <- format(days, "%a (%d/%m)")
  col_dates <- col_dates_from_labels(names(tbl), min(df_base$matchup_start))

  col_fmt_sum <- game_tbl_col_fmt(tbl, days[1], max(days), col_dates, type = "sum", starter_count = 10)
  expect_null(cell_style(col_fmt_sum, labels[2], 10))
  expect_equal(cell_style(col_fmt_sum, labels[2], 11), alert_red)

  col_fmt_sum_8 <- game_tbl_col_fmt(tbl, days[1], max(days), col_dates, type = "sum", starter_count = 8)
  expect_null(cell_style(col_fmt_sum_8, labels[2], 8))
  expect_equal(cell_style(col_fmt_sum_8, labels[2], 9), alert_red)

  col_fmt_player <- game_tbl_col_fmt(tbl, days[1], max(days), col_dates)
  expect_null(cell_style(col_fmt_player, labels[2], "2"))
  expect_null(cell_style(col_fmt_player, labels[2], 11))
})
