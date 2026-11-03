# FTY matchup weeks ------------------------------------------------------

dfs_fty_nba_mup_weeks <-
  dfs_fty_schedule |>
  map(\(x) as_tibble(x)) |>
  bind_rows(.id = "league_id") |>
  distinct(league_id, matchup_period, matchup_start, matchup_end, matchup) |>
  left_join(
    df_nba_schedule |>
      select(game_id, game_date, weekday, weekday_date, team, opponent, scheduled_to_play, home),
    by = join_by(matchup_start <= game_date, matchup_end >= game_date)
  ) |>
  (\(x) {
    x |>
      bind_rows(
        x |>
          distinct(league_id, matchup_period, matchup_start, matchup_end, matchup) |>
          mutate(matchup_end_plus = matchup_end + ddays(2), ) |>
          inner_join(
            select(x, -starts_with("matchup")),
            by = join_by(league_id, matchup_end < game_date, matchup_end_plus >= game_date)
          ) |>
          select(-c(matchup_end_plus))
      )
  })() |>
  mutate(
    mup_seq = dense_rank(game_date),
    .by = c(league_id, matchup_period),
    .after = weekday
  ) |>
  na.omit() |> # Post Fantasy has no game dates, so its rows are all NA
  nest_by(league_id) |>
  deframe() |>
  map(\(x) {
    nest_by(x, matchup_period, matchup) |>
      mutate(
        data = list(
          data |>
            arrange(mup_seq) |>
            pivot_wider(
              id_cols = team,
              names_from = weekday_date,
              values_from = scheduled_to_play,
              values_fill = 0
            ) |>
            arrange(team) |>
            filter(!is.na(team)) |>
            mutate(team = as.factor(team), Pin = 1, .after = team) |>
            rename(Team = team)
        )
      ) |>
      arrange(matchup_period) |>
      ungroup() |>
      select(-matchup_period) |>
      deframe()
  })


# Write data -------------------------------------------------------------

usethis::use_data(dfs_fty_nba_mup_weeks, overwrite = TRUE)
