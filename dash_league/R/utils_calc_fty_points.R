#' Calculate weighted fantasy points
#'
#' @description Sum each stat column multiplied by its league weight, giving a
#' player's projected fantasy points for the row's stats.
#'
#' @param df A data frame containing the league's stat columns.
#' @param cat_weights A data frame with `nba_category` and `points`.
#'
#' @return A numeric vector, or `NA` when the league scores no weighted categories.
#'
#' @noRd
#'
calc_fty_points <- function(df, cat_weights) {
  weights <- cat_weights |>
    filter(!is.na(points)) |>
    distinct(nba_category, points)

  cols <- intersect(weights$nba_category, names(df))
  if (nrow(weights) == 0 || length(cols) == 0) {
    return(rep(NA_real_, nrow(df)))
  }

  w <- weights$points[match(cols, weights$nba_category)]
  mat <- as.matrix(df[cols])
  mat[is.na(mat)] <- 0

  as.numeric(mat %*% w)
}
