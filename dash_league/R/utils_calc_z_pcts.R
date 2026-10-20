#' calc_z_scores
#'
#' @description Calculate z-scores
#'
#' @return A dataframe containing z-score calculations
#'
#' @noRd
#'
calc_z_pcts <- function(df) {
  missing <- setdiff(c("fgm", "fga", "ftm", "fta"), names(df))
  if (length(missing) > 0) {
    df <- df |>
      mutate(!!!rlang::set_names(rep(list(0), length(missing)), missing))
  }

  df |>
    mutate(
      fg_pct = coalesce(fgm / fga, 0),
      ft_pct = coalesce(ftm / fta, 0),
      fg_impact = (fg_pct - (sum(fgm, na.rm = TRUE) / sum(fga, na.rm = TRUE))) * fga,
      ft_impact = (ft_pct - (sum(ftm, na.rm = TRUE) / sum(fta, na.rm = TRUE))) * fta,
      fg_z = (fg_impact - mean(fg_impact, na.rm = TRUE)) / sd(fg_impact, na.rm = TRUE),
      ft_z = (ft_impact - mean(ft_impact, na.rm = TRUE)) / sd(ft_impact, na.rm = TRUE),
    ) |>
    select(-ends_with("impact"))
}
