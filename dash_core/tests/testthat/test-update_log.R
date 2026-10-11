test_that("update_log_row matches the util.update_log columns", {
  t <- as.POSIXct("2024-01-02 03:04:05", tz = "Pacific/Auckland")
  row <- core:::update_log_row("dashboard:base", TRUE, cadence = "daily", task_time = t)

  expect_equal(
    names(row),
    c("task", "task_time", "cadence", "success", "error_message", "source", "job_kickoff")
  )
  expect_equal(row$task, "dashboard:base")
  expect_equal(row$task_time, t)
  expect_equal(row$cadence, "daily")
  expect_true(row$success)
  expect_true(is.na(row$error_message))
  expect_true(is.na(row$source))
  expect_true(is.na(row$job_kickoff))
})

test_that("source and job_kickoff are carried through", {
  kickoff <- as.POSIXct("2024-06-01 12:00:00", tz = "UTC")
  row <- core:::update_log_row(
    "dashboard:espn-95537",
    TRUE,
    source = "scs.nba.fty.league_dash",
    job_kickoff = kickoff
  )

  expect_equal(row$source, "scs.nba.fty.league_dash")
  expect_s3_class(row$job_kickoff, "POSIXct")
  expect_equal(row$job_kickoff, kickoff)
})

test_that("a failure carries its short stage and reason", {
  row <- core:::update_log_row("dashboard:espn-95537", FALSE, error = "docker build: boom")

  expect_false(row$success)
  expect_equal(row$error_message, "docker build: boom")
})

test_that("a blank cadence falls back to 'all'", {
  expect_equal(core:::update_log_row("dashboard:x", TRUE, cadence = "")$cadence, "all")
  expect_equal(core:::update_log_row("dashboard:x", TRUE, cadence = NULL)$cadence, "all")
})

test_that("update_log_row rejects a missing task", {
  expect_error(core:::update_log_row("", TRUE))
  expect_error(core:::update_log_row(NULL, TRUE))
})

test_that("log_update warns and returns FALSE when the section is absent", {
  expect_warning(
    ok <- log_update("dashboard:x", TRUE, section = "no-such-section"),
    "could not write util.update_log row"
  )
  expect_false(ok)
})
