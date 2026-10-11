# The greatest superset of categories
cats <- c("min", "fgm", "fga", "fg3_m", "ftm", "fta", "pts", "reb", "ast", "stl", "blk", "tov", "pf", "dd2", "td3")
cur_date <- as.Date(format(Sys.time(), tz = "America/New_York"))
cur_season <- core::nba_season()
prev_season <- str_replace_all(cur_season, "\\d+", \(x) as.character(as.integer(x) - 1))
last_update <-
  tbl(db_con, I("util.update_log")) |>
  filter(successful_run) |>
  summarise(process_date = max(process_date)) |>
  as_tibble() |>
  pull(process_date)

usethis::use_data(cur_date, last_update, overwrite = TRUE)
