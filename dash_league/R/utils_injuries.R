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


latest_predicted_return <- function(forecasts) {
  forecasts |>
    filter(censored, !is.na(pred_return_date)) |>
    slice_max(prediction_date, by = c(player_id, spell_id), with_ties = FALSE) |>
    slice_max(injury_start_date, by = player_id, with_ties = FALSE) |>
    select(player_id, pred_return_date)
}


attach_predicted_injury_status <- function(df, returns, cur_date) {
  df |>
    left_join(returns, by = join_by(player_id)) |>
    mutate(
      inj_status_pred = if_else(
        game_date >= cur_date &
          inj_status %in% c("Out", "Doubtful", "Questionable") &
          !is.na(pred_return_date) &
          game_date >= pred_return_date,
        "Available",
        inj_status
      )
    )
}


next_game_injury_status <- function(df, cur_date) {
  df |>
    filter(game_date >= cur_date) |>
    slice_min(game_date, by = player_id, with_ties = FALSE) |>
    select(player_id, inj_status_pred)
}
