# Player stat columns: the canonical category vocabulary, limited to the
# columns the player box-score view exposes, minus deliberate exclusions.
# The exclusion list is the deliberate part: a stat the vocabulary and the view
# both carry but the player pipeline must not treat as a category. plus_minus is
# game context, not a fantasy category, and would otherwise flow into rolling
# stats, game logs and comparisons. A stat that is newly available and wanted is
# picked up automatically; only available-but-unwanted stats belong here.
player_stat_exclusions <- "plus_minus"

player_box_score_cols <-
  tbl(db_con, I("nba.player_box_score_vw")) |>
  colnames()

player_stat_cols <-
  tbl(db_con, I("fty.category_label")) |>
  select(nba_category, display_order) |>
  arrange(display_order, nba_category) |>
  as_tibble() |>
  pull(nba_category) |>
  intersect(player_box_score_cols) |>
  setdiff(player_stat_exclusions)
cur_date <- as.Date(format(Sys.time(), tz = "America/New_York"))
cur_season <- core::nba_season()
prev_season <- str_replace_all(cur_season, "\\d+", \(x) as.character(as.integer(x) - 1))
last_update <-
  tbl(db_con, I("util.update_log")) |>
  filter(success) |>
  summarise(task_time = max(task_time)) |>
  as_tibble() |>
  pull(task_time)

usethis::use_data(cur_date, last_update, overwrite = TRUE)
