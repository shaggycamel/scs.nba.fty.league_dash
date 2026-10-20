# Player Comparison ------------------------------------------------------

dfs_player_comparison <- map(set_names(as.character(unique(df_fty_base$league_id))), \(lg) {
  map(set_names(names(dfs_rolling_stats)), \(rl) {
    df_inr <- dfs_rolling_stats[[rl]] |>
      filter(season == cur_season) |>
      slice_max(game_date, by = player_id, with_ties = FALSE)

    free_agents <- pluck(dfs_fty_free_agents, as.character(lg), .default = tibble(player_id = integer())) |>
      select(player_id) |>
      distinct() |>
      mutate(free_agent = TRUE)

    # Shooting z-scores come from the raw counts: rescaling fgm/fga/ftm/fta first
    # would change the percentages and attempt weights they are built from.
    df_compare <- df_inr |> calc_z_pcts()

    comparison_meta <- df_fty_cats |>
      filter(
        league_id == lg,
        (category_role == "scored" & !is_ratio) |
          (category_role == "derived" & str_like(nba_category, "%_z")),
        nba_category %in% colnames(df_compare)
      ) |>
      distinct(nba_category, higher_is_better)

    higher_cols <- comparison_meta |>
      filter(higher_is_better) |>
      pull(nba_category)

    lower_cols <- comparison_meta |>
      filter(!higher_is_better) |>
      pull(nba_category)

    df_compare |>
      mutate(
        across(all_of(higher_cols), \(x) round(scales::rescale(x), 2)),
        # Invert the categories where a low value is the good outcome (eg turnovers)
        across(all_of(lower_cols), \(x) round(scales::rescale(-x), 2))
      ) |>
      pivot_longer(
        cols = all_of(comparison_meta$nba_category),
        names_to = "stat"
      ) |>
      (\(x) {
        bind_rows(
          # Moved Excels at to happen reactively in mod file
          slice_min(x, value, n = 3, by = c(player_id, player_name)) |>
            mutate(performance = "Weak At")
        )
      })() |>
      mutate(stat_value = paste0(stat, " (", round(value, 2), ")")) |>
      summarise(
        stat_value = paste(stat_value, collapse = "\n"),
        .by = c(player_id, player_name, team, inj_status, performance)
      ) |>
      pivot_wider(names_from = performance, values_from = stat_value) |>
      left_join(
        df_inr |>
          select(player_id, min, any_of(unique(df_fty_cats$nba_category))),
        by = join_by(player_id)
      ) |>
      calc_z_pcts() |>
      left_join(free_agents, by = join_by(player_id)) |>
      left_join(
        tibble(team = names(ls_nba_teams), team_id = ls_nba_teams),
        by = join_by(team)
      ) |>
      relocate(team_id, .before = team) |>
      arrange(desc(min)) |>
      # to lighten the size of final object
      select(-any_of("pf"), -ends_with("_pct"), -matches("f[g|t][m|a]"))
  })
})


# Write data -------------------------------------------------------------

usethis::use_data(dfs_player_comparison, overwrite = TRUE)
