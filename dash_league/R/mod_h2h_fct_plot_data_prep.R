plot_data_prep <- function(df_base, rv_carry_thru) {
  stat_weights <- df_fty_cat_weights |>
    filter(
      league_id == as.integer(rv_carry_thru$league_id),
      !is.na(points)
    ) |>
    arrange(display_order, nba_category)

  df_base |>
    select(
      competitor,
      player_id,
      player_name,
      inj_status,
      matches("f[g|t][m|a]"),
      any_of(unname(pluck(ls_lo_lg_cats, as.character(rv_carry_thru$league_id))[["Categories"]]))
    ) |>
    pivot_longer(c(
      matches("f[g|t][m|a]"),
      any_of(unname(pluck(ls_lo_lg_cats, as.character(rv_carry_thru$league_id))[["Categories"]]))
    )) |>
    mutate(value = if_else(inj_status == "Out", 0, value, missing = value)) |>
    summarise(
      value = sum(value, na.rm = TRUE),
      .by = c(competitor, player_id, player_name, name)
    ) |>
    arrange(desc(value)) |>
    (\(x) {
      if (nrow(stat_weights) > 0) {
        weighted <- x |>
          inner_join(
            stat_weights |> select(nba_category, points),
            by = join_by(name == nba_category)
          ) |>
          mutate(points_value = value * points)

        category_rows <- weighted |>
          summarise(
            label = paste0(
              "Total - ", round(sum(points_value, na.rm = TRUE), 1), "\n\n",
              paste(str_c(player_name, " - ", round(points_value, 1)), collapse = "\n")
            ),
            value = sum(points_value, na.rm = TRUE),
            is_overall = FALSE,
            .by = c(competitor, name)
          )

        overall_rows <- weighted |>
          summarise(
            points_value = sum(points_value, na.rm = TRUE),
            .by = c(competitor, player_id, player_name)
          ) |>
          summarise(
            label = paste0(
              "Total - ", round(sum(points_value, na.rm = TRUE), 1), "\n\n",
              paste(str_c(player_name, " - ", round(points_value, 1)), collapse = "\n")
            ),
            value = sum(points_value, na.rm = TRUE),
            is_overall = TRUE,
            .by = competitor
          ) |>
          mutate(name = "FTY Pts")

        bind_rows(overall_rows, category_rows) |>
          mutate(
            name = ordered(name, c("FTY Pts", stat_weights$nba_category)),
            name = fct_drop(name)
          ) |>
          arrange(competitor, name)
      } else {
        cat_meta <- df_fty_cat_weights |>
          filter(league_id == as.integer(rv_carry_thru$league_id)) |>
          distinct(nba_category, higher_is_better)

        f_inr <- \(col_string) {
          m_col <- sym(str_c(col_string, "m"))
          a_col <- sym(str_c(col_string, "a"))

          x |>
            filter(str_detect(name, col_string)) |>
            pivot_wider(names_from = name, values_from = value) |>
            summarise(
              #fmt: skip
              label = paste0(
                "Total - ", round(sum(!!m_col, na.rm = TRUE), 0), "/", round(sum(!!a_col, na.rm = TRUE), 0), " (", label_percent(accuracy = 0.01)(sum(!!m_col, na.rm = TRUE)/sum(!!a_col, na.rm = TRUE)),")\n\n",
                paste(str_c(player_name, " - ", round(!!m_col, 0), "/", round(!!a_col, 0)), collapse = "\n")
              ),
              name = str_c(col_string, "_pct"),
              value = sum(!!m_col, na.rm = TRUE) / sum(!!a_col, na.rm = TRUE),
              .by = competitor
            )
        }

        bind_rows(
          f_inr("fg"),
          f_inr("ft"),
          x |>
            filter(!str_like(name, "f[g|t][m|a]")) |>
            summarise(
              # fmt: skip
              label = paste0(
                    "Total - ", round(sum(value, na.rm = TRUE), 1), "\n\n",
                    paste(str_c(player_name, " - ", round(value, 1)), collapse = "\n")
                  ),
              value = sum(value, na.rm = TRUE),
              .by = c(competitor, name)
            )
        ) |>
          mutate(
            name = ordered(name, c("reb", "blk", "stl", "tov", "ast", "pts", "fg3_m", "fg_pct", "ft_pct", "dd2", "td3")),
            name = fct_drop(name),
            name_chr = as.character(name),
            is_overall = FALSE
          ) |>
          left_join(cat_meta, by = join_by(name_chr == nba_category)) |>
          mutate(is_negative = coalesce(!higher_is_better, FALSE)) |>
          select(-name_chr, -higher_is_better) |>
          arrange(competitor, name)
      }
    })()
}


# Season totals for the postseason plot. The past data carries a two-day
# lookahead per matchup, so cut at each matchup's own end to avoid double counting.
postseason_base_data_prep <- function(df_h2h_past, selected_competitor_id, competitor_name) {
  competitor_data <- df_h2h_past |>
    map(\(matchup) pluck(matchup, as.character(selected_competitor_id))) |>
    compact()

  # nothing completed yet for this competitor
  if (length(competitor_data) == 0) {
    return(tibble())
  }

  competitor_data |>
    list_rbind() |>
    filter(game_date <= matchup_end) |>
    mutate(competitor = competitor_name)
}
