# H2H Past ---------------------------------------------------------------

dfs_h2h_past <- dfs_fty_roster |>
  list_rbind(names_to = "league_id") |>
  filter(assigned_date < cur_date) |>
  left_join(
    select(df_nba_schedule, team, game_date, scheduled_to_play, game_id),
    by = join_by(player_team == team, assigned_date == game_date)
  ) |>
  filter(!is.na(game_id)) |>
  select(-c(game_id, season_type, begin_date, end_date, player_acquisition_type, player_injury_status)) |>
  rename(game_date = assigned_date) |>
  left_join(
    df_nba_player_box_score |>
      select(-c(contains("season"), espn_id, yahoo_id, player_name)),
    by = join_by(player_id, game_date, player_team == team)
  ) |>
  (\(df) {
    bind_rows(
      df,
      df |>
        distinct(league_id, matchup_period, matchup_start, matchup_end) |>
        mutate(matchup_end_plus = matchup_end + ddays(2), ) |>
        left_join(
          select(df, -starts_with("matchup")),
          by = join_by(league_id, matchup_end < game_date, matchup_end_plus >= game_date)
        )
      # select(-matchup_end_plus)
    )
  })() |>
  mutate(fmt_date = format(game_date, "%a (%d/%m)")) |>
  distinct() |> # FOR SAFETY
  nest_by(league_id, matchup_period, competitor_id) |>
  nest_by(league_id, matchup_period) |>
  nest_by(league_id) |>
  deframe() |>
  map(\(x) map(deframe(x), \(y) deframe(y)))


# H2H Today and Future ---------------------------------------------------

dfs_h2h_future_generation <- function() {
  #
  # fty roster & free agents
  df <- dfs_fty_roster |>
    list_rbind(names_to = "league_id") |>
    slice_max(assigned_date, by = c(league_id, competitor_id)) |>
    mutate(competitor_id = as.character(competitor_id)) |>
    select(league_id, platform, competitor_id, player_id, player_name, player_team) |>
    bind_rows(
      dfs_fty_free_agents |>
        list_rbind(names_to = "league_id") |>
        mutate(competitor_id = "free_agent") |>
        select(league_id, platform, competitor_id, player_id, player_name, player_team)
    ) |>

    # fty schedule
    left_join(
      dfs_fty_schedule |>
        list_rbind(names_to = "league_id") |>
        # To handle post sesason when cur_date > max(matchup_end)
        # (\(df_t) {
        #   if (nrow(filter(df_t, cur_date <= matchup_end)) > 0) {
        #     filter(df_t, cur_date <= matchup_end)
        #   } else {
        #     slice_max(df_t, matchup_end, by = league_id)
        #   }
        # })() |>
        filter(cur_date <= matchup_end) |>
        mutate(
          matchup_end = if_else(matchup_period == 99, max(matchup_end[matchup_period != 99]), matchup_end),
          .by = league_id
        ) |>
        mutate(competitor_id = as.character(competitor_id)) |>
        select(league_id, platform, matchup_period, matchup_start, matchup_end, competitor_id, opponent_id),
      by = join_by(league_id, platform, competitor_id),
      relationship = "many-to-many"
    ) |>
    mutate(
      matchup_period = as.character(matchup_period),
      matchup_period = if_else(competitor_id == "free_agent", "free_agent", matchup_period),
      scheduled_to_play = 1
    ) |>
    fill_free_agent_window() |>

    # Rolling stats
    left_join(
      dfs_rolling_stats |>
        list_rbind(names_to = "window") |>
        # To handle post sesason when cur_date > max(game_date)
        # (\(df_t) {
        #   if (nrow(filter(df_t, game_date >= cur_date)) > 0) {
        #     filter(df_t, game_date >= cur_date) |>
        #       cross_join(tibble(league_id = names(dfs_league_overview)))
        #   } else {
        #     slice_max(df_t, game_date, by = player_id) |>
        #       cross_join(
        #         dfs_fty_schedule |>
        #           list_rbind(names_to = "league_id") |>
        #           distinct(league_id, matchup_end) |>
        #           slice_max(matchup_end, by = league_id)
        #       ) |>
        #       select(-game_date) |>
        #       rename(game_date = matchup_end)
        #   }
        # })() |>
        filter(game_date >= cur_date) |>
        select(
          window,
          player_id,
          inj_status,
          inj_reason,
          game_date,
          dow,
          game_id,
          team,
          opponent,
          home,
          any_of(player_stat_cols)
        ),
      by = join_by(player_id, player_team == team, matchup_start <= game_date, matchup_end >= game_date),
      relationship = "many-to-many"
    ) |>
    mutate(fmt_date = format(game_date, "%a (%d/%m)")) |>
    distinct() |> # FOR SAFETY
    filter(
      matchup_period != "99" | game_date == min(game_date),
      .by = c(league_id, competitor_id, player_id, matchup_period)
    )

  # Add matchup lookahead
  # Not sure how this will look when cur_date == matchup_end
  # THINK THIS CREATES DUPS
  df <- bind_rows(
    df,
    df |>
      filter(matchup_period != "99") |>
      distinct(league_id, matchup_period, matchup_start, matchup_end) |>
      mutate(matchup_end_plus = matchup_end + ddays(2)) |>
      left_join(
        select(df, -starts_with("matchup")),
        by = join_by(league_id, matchup_end < game_date, matchup_end_plus >= game_date)
      )
    # select(-matchup_end_plus)
  )

  if (nrow(df) == 0) {
    df
  } else {
    df |>
      nest_by(league_id, matchup_period, competitor_id, window) |>
      nest_by(league_id, matchup_period, competitor_id) |>
      nest_by(league_id, matchup_period) |>
      nest_by(league_id) |>
      deframe() |>
      map(\(x) map(deframe(x), \(y) map(deframe(y), \(z) deframe(z))))
  }
}

dfs_h2h_future <- dfs_h2h_future_generation()


# Write data -------------------------------------------------------------

usethis::use_data(
  dfs_h2h_past,
  dfs_h2h_future,
  overwrite = TRUE
)
