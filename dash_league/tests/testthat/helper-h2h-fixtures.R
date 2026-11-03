# Fixtures for the h2h table prep functions.
#
# table_data_prep() and table_sum_data_prep() read a small slice of df_base:
# one row per player per game day, plus the matchup boundary columns. These
# helpers build that slice directly so the tests don't need a database.
#
# Game days are anchored to cur_date by the caller, because both functions
# compare it against matchup_end to decide whether a matchup is still running,
# and cur_date is baked into the package data at build time.

# Package data objects (LazyData) are not bindings in the namespace, so
# testthat::local_mocked_bindings() cannot reach them. Functions read them from
# the attached package environment, so swap them in there and restore on exit.
local_pkg_data <- function(..., .env = parent.frame()) {
  pkg <- as.environment("package:league")
  bindings <- list(...)
  nms <- names(bindings)

  missing <- nms[!rlang::env_has(pkg, nms)]
  if (length(missing) > 0) {
    cli::cli_abort("Can't find package data binding for {.field {missing}}.")
  }

  unlocked <- rlang::env_binding_unlock(pkg, nms)
  rlang::env_bind(pkg, !!!bindings)

  restore <- function() rlang::env_binding_lock(pkg, nms[unlocked])
  withr::defer(restore(), envir = .env)
}

fake_player <- function(id, name, team, competitor, games, inj_status = NA_character_) {
  list(
    id = id,
    name = name,
    team = team,
    competitor = competitor,
    games = games,
    inj_status = inj_status
  )
}

fake_h2h_base <- function(players, days, matchup_end = max(days), matchup_end_plus = as.Date(NA)) {
  players |>
    map(\(p) {
      tibble(
        competitor = p$competitor,
        competitor_id = match(p$competitor, c("Us", "Them")),
        player_team = p$team,
        player_id = p$id,
        player_name = p$name,
        inj_status = p$inj_status,
        game_date = days,
        fmt_date = format(days, "%a (%d/%m)"),
        # Recycled so one roster can be reused across fixtures of any length.
        scheduled_to_play = rep_len(p$games, length(days)),
        matchup_start = min(days),
        matchup_end = matchup_end,
        matchup_end_plus = matchup_end_plus,
        tense = "future"
      )
    }) |>
    list_rbind()
}

# table_data_prep() left-joins the grey-player frame on player_id and
# competitor_id. An empty one means nobody was added to or dropped mid-matchup.
no_grey_players <- function() {
  tibble(
    player_id = integer(),
    competitor_id = integer(),
    grey_intervals = list()
  )
}

# dfs_h2h_past nests league -> matchup period -> competitor -> games. Flatten
# it to one row per game with the three nesting keys as integer columns.
flatten_h2h_past <- function(past) {
  purrr::imap(past, \(lg, lg_id) {
    purrr::imap(lg, \(mp, mp_id) {
      purrr::imap(mp, \(cp, cp_id) {
        dplyr::mutate(
          cp,
          league_id = as.integer(lg_id),
          matchup_period = as.integer(mp_id),
          competitor_id = suppressWarnings(as.integer(cp_id))
        )
      }) |>
        purrr::list_rbind()
    }) |>
      purrr::list_rbind()
  }) |>
    purrr::list_rbind()
}

# The roster used across both test files: Ann and Bob share a competitor so the
# summary table has something to add up, and Bob is Out so his cells carry the
# "*" marker that as.numeric() cannot read on its own.
h2h_test_roster <- function() {
  list(
    fake_player(1, "Ann", "LAL", "Us", c(1, 0, 1, 1)),
    fake_player(2, "Bob", "BOS", "Us", c(1, 1, 0, 1), inj_status = "Out"),
    fake_player(3, "Cyd", "NYK", "Them", c(0, 1, 1, 0))
  )
}
