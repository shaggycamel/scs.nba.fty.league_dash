fill_free_agent_window <- function(df) {
  df |>
    mutate(
      matchup_start = replace_na(matchup_start, min(matchup_start, na.rm = TRUE)),
      matchup_end = replace_na(matchup_end, max(matchup_end, na.rm = TRUE)),
      .by = league_id
    )
}
