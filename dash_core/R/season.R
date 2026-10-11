#' Current NBA season
#'
#' The season string (e.g. `"2025-26"`), read from the `NBA_SEASON` environment
#' variable. This is the single source of truth for the season, shared by the
#' data-generation scripts, the league listing and the entry point, so the
#' default only lives in one place. An unset or empty `NBA_SEASON` falls back to
#' the default.
#'
#' @return A string.
#' @export
nba_season <- function() {
  season <- Sys.getenv("NBA_SEASON")
  if (nzchar(season)) season else "2025-26"
}
