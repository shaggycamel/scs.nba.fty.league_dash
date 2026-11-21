forecast_stat_map <- c(
  fga = "pred_fga",
  fgm = "pred_fgm",
  fg3_a = "pred_fg3a",
  fg3_m = "pred_fg3m",
  fta = "pred_fta",
  ftm = "pred_ftm",
  oreb = "pred_oreb",
  dreb = "pred_dreb",
  ast = "pred_ast",
  stl = "pred_stl",
  blk = "pred_blk",
  tov = "pred_tov",
  pf = "pred_pf",
  pts = "pred_pts",
  reb = "pred_reb"
)


forecast_box_score_stats <- function(forecast) {
  forecast |>
    rename(all_of(forecast_stat_map)) |>
    rename(min = minutes_if_plays) |>
    select(player_id, any_of("game_id"), min, all_of(names(forecast_stat_map)))
}
