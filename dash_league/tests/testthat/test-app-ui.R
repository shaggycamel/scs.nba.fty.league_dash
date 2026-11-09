test_that("league UI heartbeats itself and entry on activity", {
  withr::local_envvar(NBA_ENTRY_URL = "https://example-entry.hf.space")
  head <- as.character(htmltools::renderTags(app_ui(NULL))$head)

  expect_match(head, 'window.NBA_ENTRY_ORIGIN = "https://example-entry.hf.space"', fixed = TRUE)
  expect_match(head, "'pointermove'", fixed = TRUE)
  expect_match(head, "THROTTLE_MS = 30000", fixed = TRUE)
  expect_false(grepl("setInterval", head, fixed = TRUE))
})
