test_that("future injuries use each team's latest report", {
  injuries <- tibble(
    game_date = as.Date(c("2026-04-12", "2026-10-21", "2026-10-21", "2026-10-22", "2026-04-12")),
    team_slug = c("CLE", "CLE", "PHI", "CLE", "CLE"),
    nba_id = c(201935L, 201935L, 999L, 1628386L, 321L),
    status = c("Out", "Available", "Out", "Questionable", "Out"),
    reason = c("Rest", NA, "Ankle", "Knee", "Rest")
  )
  future <- tibble(
    team = c("CLE", "CLE", "PHI", "CLE", "CLE"),
    player_id = c(201935L, 1628386L, 999L, 123L, 321L)
  )

  out <- attach_current_injury_status(future, injuries, as.Date("2026-10-22"))

  expect_equal(
    out$inj_status,
    c("Available", "Questionable", "Out", "Available", "Available")
  )
  expect_equal(out$inj_reason, c(NA, "Knee", "Ankle", NA, NA))
})
