#' Snapshot the nearest depth chart per team
#'
#' @description Keeps every row on each team's earliest date at or after
#'   `build_date`, falling back to the team's latest date when no upcoming game
#'   remains.
#'
#' @param df A team-hierarchy data frame with `team_abbreviation` and `game_date`.
#' @param build_date The build date; today counts as upcoming.
#'
#' @return `df` filtered to one game date per team.
#'
#' @noRd
team_depth_snapshot <- function(df, build_date) {
  upcoming <- df |>
    filter(game_date >= build_date)

  if (nrow(upcoming) > 0) {
    upcoming <- upcoming |>
      filter(game_date == min(game_date), .by = team_abbreviation)
  }

  df |>
    filter(game_date == max(game_date), .by = team_abbreviation) |>
    filter(!team_abbreviation %in% upcoming$team_abbreviation) |>
    bind_rows(upcoming)
}
