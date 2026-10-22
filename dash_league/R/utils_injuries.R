latest_injury_report <- function(injuries, cur_date, days = 30) {
  recent <- injuries |>
    filter(game_date >= cur_date - days, !is.na(nba_id))

  latest_team <- recent |>
    distinct(team_slug, game_date) |>
    slice_max(game_date, by = team_slug)

  recent |>
    inner_join(latest_team, by = join_by(team_slug, game_date)) |>
    arrange(desc(game_date)) |>
    distinct(team_slug, nba_id, .keep_all = TRUE) |>
    transmute(
      team = team_slug,
      player_id = as.integer(nba_id),
      inj_status = status,
      inj_reason = reason
    )
}

attach_current_injury_status <- function(df, injuries, cur_date, days = 30) {
  lookup <- latest_injury_report(injuries, cur_date, days) |>
    rename(current_inj_status = inj_status, current_inj_reason = inj_reason)

  df |>
    left_join(lookup, by = join_by(team, player_id)) |>
    mutate(
      inj_status = coalesce(current_inj_status, "Available"),
      inj_reason = current_inj_reason
    ) |>
    select(-current_inj_status, -current_inj_reason)
}
