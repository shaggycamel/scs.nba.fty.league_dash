points_data_prep <- function(df_base, cat_weights) {
  weights <- cat_weights |>
    filter(!is.na(points)) |>
    select(nba_category, fmt_category, display_order, points)

  weighted_cols <- intersect(weights$nba_category, colnames(df_base))

  if (length(weighted_cols) == 0) {
    return(tibble(
      competitor = df_base$competitor[0],
      name = character(),
      fmt_category = character(),
      display_order = double(),
      value = double(),
      points = double()
    ))
  }

  df_base |>
    select(competitor, inj_status, any_of(weighted_cols)) |>
    pivot_longer(any_of(weighted_cols), names_to = "name", values_to = "value") |>
    mutate(value = if_else(inj_status == "Out", 0, value, missing = value)) |>
    summarise(value = sum(value, na.rm = TRUE), .by = c(competitor, name)) |>
    left_join(weights, by = join_by(name == nba_category)) |>
    mutate(points = value * points) |>
    arrange(competitor, display_order, name) |>
    select(competitor, name, fmt_category, display_order, value, points)
}
