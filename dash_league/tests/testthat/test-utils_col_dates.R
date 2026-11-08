test_that("labels keep their year across new year", {
  # format(x, "%a (%d/%m)") drops the year, so "Mon (04/01)" is ambiguous, and
  # parsing it back fills in the current year - wrong for a matchup week
  # straddling new year.
  labels <- c("Tue (30/12)", "Wed (31/12)", "Thu (01/01)", "Fri (02/01)")
  dts <- col_dates_from_labels(labels, as.Date("2026-12-30"))

  expect_equal(unname(dts), as.Date(c("2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02")))
  expect_equal(unname(format(dts, "%Y")), c("2026", "2026", "2027", "2027"))
})

test_that("col_dates_from_labels resolves labels against the matchup start", {
  # The matchup-week tables arrive pivoted, with Team and Pin ahead of the days.
  col_names <- c("Team", "Pin", "Mon (27/10)", "Tue (28/10)", "Wed (29/10)")

  expect_equal(
    col_dates_from_labels(col_names, as.Date("2025-10-27")),
    set_names(as.Date(c("2025-10-27", "2025-10-28", "2025-10-29")), col_names[-(1:2)])
  )
})

test_that("col_dates_from_labels rolls the year over at new year", {
  col_names <- c("Team", "Pin", "Mon (29/12)", "Thu (01/01)", "Tue (06/01)")
  dts <- col_dates_from_labels(col_names, as.Date("2025-12-29"))

  expect_equal(unname(dts), as.Date(c("2025-12-29", "2026-01-01", "2026-01-06")))
})

test_that("col_dates_from_labels handles days with no games", {
  # Columns are the days that have games, not a contiguous run: matchup 17 skips
  # the all-star break, and a matchup whose first day has no games has no column
  # for it. Walking days forward from matchup_start would mislabel both.
  all_star <- c("Team", "Pin", "Mon (09/02)", "Thu (12/02)", "Thu (19/02)", "Tue (24/02)")
  expect_equal(
    unname(col_dates_from_labels(all_star, as.Date("2026-02-09"))),
    as.Date(c("2026-02-09", "2026-02-12", "2026-02-19", "2026-02-24"))
  )

  late_start <- c("Team", "Pin", "Tue (21/10)", "Wed (22/10)")
  expect_equal(
    unname(col_dates_from_labels(late_start, as.Date("2025-10-20"))),
    as.Date(c("2025-10-21", "2025-10-22"))
  )
})

test_that("col_dates_from_labels copes with no date columns", {
  expect_equal(
    col_dates_from_labels(c("Team", "Pin"), as.Date("2025-10-27")),
    set_names(as.Date(character()), character())
  )
})

# The real shapes that broke the old positional arithmetic.
matchup_1 <- c(
  "Team",
  "Pin",
  "Tue (21/10)",
  "Wed (22/10)",
  "Thu (23/10)",
  "Fri (24/10)",
  "Sat (25/10)",
  "Sun (26/10)",
  "Mon (27/10)",
  "Tue (28/10)"
)
matchup_6 <- c(
  "Team",
  "Pin",
  "Mon (24/11)",
  "Tue (25/11)",
  "Wed (26/11)",
  "Fri (28/11)",
  "Sat (29/11)",
  "Sun (30/11)",
  "Mon (01/12)",
  "Tue (02/12)"
)

test_that("pin_columns counts the pinned day through to the matchup end", {
  # Matchup 1 has no column for its first day, 20 Oct, because no games were on.
  dts <- col_dates_from_labels(matchup_1, as.Date("2025-10-20"))
  cols <- pin_columns(dts, as.Date("2025-10-21"), as.Date("2025-10-20"), as.Date("2025-10-26"), "+")

  expect_equal(cols, c("Tue (21/10)", "Wed (22/10)", "Thu (23/10)", "Fri (24/10)", "Sat (25/10)", "Sun (26/10)"))
})

test_that("pin_columns skips days off mid-matchup", {
  # Matchup 6 has no column for Thanksgiving, 27 Nov.
  dts <- col_dates_from_labels(matchup_6, as.Date("2025-11-24"))
  cols <- pin_columns(dts, as.Date("2025-11-24"), as.Date("2025-11-24"), as.Date("2025-11-30"), "+")

  expect_equal(cols, c("Mon (24/11)", "Tue (25/11)", "Wed (26/11)", "Fri (28/11)", "Sat (29/11)", "Sun (30/11)"))
})

test_that("pin_columns never counts the post-matchup days", {
  dts <- col_dates_from_labels(matchup_6, as.Date("2025-11-24"))
  forward <- pin_columns(dts, as.Date("2025-11-24"), as.Date("2025-11-24"), as.Date("2025-11-30"), "+")
  backward <- pin_columns(dts, as.Date("2025-11-30"), as.Date("2025-11-24"), as.Date("2025-11-30"), "-")

  expect_false(any(c("Mon (01/12)", "Tue (02/12)") %in% c(forward, backward)))
})

test_that("pin_columns looking back stops at the day before the pin", {
  dts <- col_dates_from_labels(matchup_6, as.Date("2025-11-24"))

  expect_equal(
    pin_columns(dts, as.Date("2025-11-28"), as.Date("2025-11-24"), as.Date("2025-11-30"), "-"),
    c("Mon (24/11)", "Tue (25/11)", "Wed (26/11)")
  )
  # Pinning the first day leaves nothing behind it.
  expect_equal(
    pin_columns(dts, as.Date("2025-11-24"), as.Date("2025-11-24"), as.Date("2025-11-30"), "-"),
    character(0)
  )
})

test_that("pin_columns spans the all-star break", {
  all_star <- c(
    "Team",
    "Pin",
    "Mon (09/02)",
    "Tue (10/02)",
    "Wed (11/02)",
    "Thu (12/02)",
    "Thu (19/02)",
    "Fri (20/02)",
    "Sat (21/02)",
    "Sun (22/02)",
    "Mon (23/02)",
    "Tue (24/02)"
  )
  dts <- col_dates_from_labels(all_star, as.Date("2026-02-09"))

  # Looking back from the first day after the break: the four days before it.
  expect_equal(
    pin_columns(dts, as.Date("2026-02-19"), as.Date("2026-02-09"), as.Date("2026-02-22"), "-"),
    c("Mon (09/02)", "Tue (10/02)", "Wed (11/02)", "Thu (12/02)")
  )
  # Looking forward, up to matchup end on 22 Feb - not the two columns past it.
  expect_equal(
    pin_columns(dts, as.Date("2026-02-19"), as.Date("2026-02-09"), as.Date("2026-02-22"), "+"),
    c("Thu (19/02)", "Fri (20/02)", "Sat (21/02)", "Sun (22/02)")
  )
})

test_that("fill_missing_days gives a day off its own column", {
  # Matchup 6 has no column for Thanksgiving, 27 Nov.
  df <- tibble(Team = "LAL", Pin = 1, `Mon (24/11)` = 1, `Wed (26/11)` = 1, `Fri (28/11)` = 1)
  filled <- fill_missing_days(df, as.Date("2025-11-24"))

  expect_equal(
    names(filled),
    c("Team", "Pin", "Mon (24/11)", "Tue (25/11)", "Wed (26/11)", "Thu (27/11)", "Fri (28/11)")
  )
  expect_equal(filled[["Thu (27/11)"]], 0)
  expect_equal(filled[["Wed (26/11)"]], 1)
})

test_that("fill_missing_days covers a matchup whose first day has no games", {
  # Matchup 1 starts Mon 20 Oct, but the season's first game is on the Tuesday.
  df <- tibble(Team = "LAL", Pin = 1, `Tue (21/10)` = 1, `Wed (22/10)` = 0)
  filled <- fill_missing_days(df, as.Date("2025-10-20"))

  expect_equal(names(filled), c("Team", "Pin", "Mon (20/10)", "Tue (21/10)", "Wed (22/10)"))
})

test_that("fill_missing_days spans the all-star break", {
  df <- tibble(Team = "LAL", Pin = 1, `Thu (12/02)` = 1, `Thu (19/02)` = 1)
  filled <- fill_missing_days(df, as.Date("2026-02-12"))

  expect_equal(str_subset(names(filled), "/"), format(as.Date("2026-02-12") + 0:7, "%a (%d/%m)"))
  expect_true(all(unlist(filled[, format(as.Date("2026-02-13") + 0:5, "%a (%d/%m)")]) == 0))
})

test_that("fill_missing_days covers a post-matchup day with no games", {
  # The tables carry the two days after the matchup. Here only the first has
  # games, so the second would otherwise be missing and the week would show one
  # trailing day where every other week shows two.
  df <- tibble(Team = "LAL", Pin = 1, `Sun (14/12)` = 1, `Mon (15/12)` = 1)
  filled <- fill_missing_days(df, as.Date("2025-12-14"), as.Date("2025-12-14"))

  expect_equal(str_subset(names(filled), "/"), c("Sun (14/12)", "Mon (15/12)", "Tue (16/12)"))
  expect_equal(filled[["Tue (16/12)"]], 0)
})

test_that("fill_missing_days covers post-matchup days when neither has games", {
  df <- tibble(Team = "LAL", Pin = 1, `Sat (13/12)` = 1, `Sun (14/12)` = 1)
  filled <- fill_missing_days(df, as.Date("2025-12-13"), as.Date("2025-12-14"))

  expect_equal(
    str_subset(names(filled), "/"),
    c("Sat (13/12)", "Sun (14/12)", "Mon (15/12)", "Tue (16/12)")
  )
})

test_that("fill_missing_days ignores a matchup_end beyond the data", {
  # Post Fantasy's matchup_end is 2999-01-01. Filling to it would lay out nine
  # centuries of columns, so the range falls back to the data itself.
  df <- tibble(Team = "LAL", Pin = 1, `Mon (24/11)` = 1, `Wed (26/11)` = 1)
  filled <- fill_missing_days(df, as.Date("2025-11-24"), as.Date("2999-01-01"))

  expect_equal(str_subset(names(filled), "/"), c("Mon (24/11)", "Tue (25/11)", "Wed (26/11)"))
})

test_that("fill_missing_days stops at the last column when given no matchup_end", {
  df <- tibble(Team = "LAL", Pin = 1, `Mon (24/11)` = 1, `Wed (26/11)` = 1)
  filled <- fill_missing_days(df, as.Date("2025-11-24"))

  expect_equal(tail(names(filled), 1), "Wed (26/11)")
})

test_that("fill_missing_days leaves a table with no gaps alone", {
  df <- tibble(Team = "LAL", Pin = 1, `Mon (24/11)` = 1, `Tue (25/11)` = 0)

  expect_equal(fill_missing_days(df, as.Date("2025-11-24")), df)
})

test_that("fill_missing_days copes with no date columns", {
  df <- tibble(Team = "LAL", Pin = 1)

  expect_equal(fill_missing_days(df, as.Date("2025-11-24")), df)
})

test_that("fill_missing_days fills the h2h table with character zeros", {
  # h2h cells are character, since an injured player's day carries a "*".
  df <- tibble(player_name = "Ann", `Mon (24/11)` = "1", `Wed (26/11)` = "1*")
  filled <- fill_missing_days(df, as.Date("2025-11-24"), fill = "0")

  expect_equal(filled[["Tue (25/11)"]], "0")
})

test_that("fill_missing_days keeps the column type it found", {
  # The filled columns feed straight into sum(), so a double dropped into integer
  # counts would quietly change the Pin column's type.
  df <- tibble(Team = "LAL", Pin = 1L, `Mon (24/11)` = 1L, `Wed (26/11)` = 1L)
  filled <- fill_missing_days(df, as.Date("2025-11-24"))

  expect_type(filled[["Tue (25/11)"]], "integer")
  expect_identical(sum(unlist(filled[1, str_subset(names(filled), "/")])), 2L)
})
