test_that("entry UI heartbeats itself and the embedded league", {
  head <- as.character(htmltools::renderTags(app_ui(NULL))$head)

  expect_match(head, "window.nbaHeartbeat", fixed = TRUE)
  expect_match(head, "league_frame", fixed = TRUE)
  expect_match(head, "mode: 'no-cors'", fixed = TRUE)
  expect_match(head, "setInterval(nbaHeartbeat, 60000)", fixed = TRUE)
  expect_false(grepl("keepalive.txt", head, fixed = TRUE))
})
