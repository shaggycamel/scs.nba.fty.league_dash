test_that("entry UI heartbeats itself and the embedded league on activity", {
  head <- as.character(htmltools::renderTags(app_ui(NULL))$head)

  expect_match(head, "window.nbaHeartbeat", fixed = TRUE)
  expect_match(head, "league_frame", fixed = TRUE)
  expect_match(head, "mode: 'no-cors'", fixed = TRUE)
  expect_match(head, "'pointermove'", fixed = TRUE)
  expect_match(head, "THROTTLE_MS = 30000", fixed = TRUE)
  expect_false(grepl("setInterval", head, fixed = TRUE))
  expect_false(grepl("keepalive.txt", head, fixed = TRUE))
})
