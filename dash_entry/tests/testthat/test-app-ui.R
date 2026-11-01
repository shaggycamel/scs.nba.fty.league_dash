test_that("entry UI pings its own origin to keep the Space awake", {
  head <- as.character(htmltools::renderTags(app_ui(NULL))$head)

  expect_match(head, "www/keepalive.txt", fixed = TRUE)
  expect_match(head, "cache: 'no-store'", fixed = TRUE)
  expect_true(file.exists(system.file("app/www/keepalive.txt", package = "entry")))
})
