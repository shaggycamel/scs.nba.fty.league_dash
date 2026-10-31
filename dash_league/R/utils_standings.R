#' standings_division_groups
#'
#' @description Ordered division groups for the standings table, or NULL when
#'   the league is not split into divisions.
#'
#' @param df A standings data frame.
#'
#' @return A tibble with `division_id` and `division_name`, or NULL.
#' @noRd
standings_division_groups <- function(df) {
  if (!all(c("division_id", "division_name") %in% names(df))) {
    return(NULL)
  }
  if (nrow(df) == 0 || any(is.na(df$division_name))) {
    return(NULL)
  }

  df |>
    distinct(division_id, division_name) |>
    arrange(division_id, division_name)
}
