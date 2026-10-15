# Player box score -------------------------------------------------------

df_nba_player_box_score <-
  tbl(db_con, I("nba.player_box_score_vw")) |>
  filter(season >= prev_season, season_type == "Regular Season", !is.na(player_id)) |>
  # filter(game_date < cur_date) |> # for testing purposes
  as_tibble() |>
  mutate(
    across(ends_with("_id"), \(x) as.integer(x)),
    across(all_of(player_stat_cols), \(x) as.double(x)),
    season = ordered(season),
    season_type = ordered(season_type, c("Pre Season", "Regular Season", "Playoffs")),
    year_season_type = fct_cross(season_type, str_sub(season, start = 6), sep = " ")
  ) |>

  # add distinct here just in case...ideally should fix duplicates in source
  distinct()


# NBA Schedule -----------------------------------------------------------

# OFTEN DUPLICATION...NEED TO FIX IN COCKROACH
# df_nba_schedule |> view()
# count(game_id) |> filter(n > 2)

df_nba_schedule <-
  tbl(db_con, I("nba.season_segments_vw")) |>
  filter(season == cur_season, season_type == "Regular Season") |>
  select(begin_date, end_date) |>
  as_tibble() |>
  pivot_longer(cols = ends_with("date"), values_to = "game_date") |>
  complete(game_date = seq.Date(min(game_date), max(game_date), by = "day")) |>
  select(game_date) |>
  left_join(
    tbl(db_con, I("nba.schedule_vw")) |>
      filter(season == cur_season, season_type == 'Regular Season') |>
      as_tibble(),
    by = join_by(game_date)
  ) |>
  mutate(
    across(ends_with("_id"), \(x) as.integer(x)),
    season = cur_season,
    season_type = "Regular Season",
    dow = wday(game_date, week_start = 1),
    weekday = wday(game_date, label = TRUE, week_start = 1),
    weekday_date = str_c(weekday, " ", format(game_date, "(%d/%m)")),
    scheduled_to_play = ifelse(!is.na(game_id), 1L, game_id) # used in h2h calculations
  )


# Season segments --------------------------------------------------------

# Might need to do work here when season ends

df_nba_season_segments <-
  tbl(db_con, I("nba.season_segments_vw")) |>
  filter(season >= prev_season) |>
  as_tibble() |>
  (\(df) {
    bind_rows(
      filter(df, cur_date > begin_date, cur_date < end_date) |>
        mutate(end_date = as.Date(cur_date)),

      setdiff(df, filter(df, cur_date > begin_date, cur_date < end_date))
    )
  })() |>
  mutate(mid_date = begin_date + (end_date - begin_date) / 2)


# Teams ------------------------------------------------------------------

ls_nba_teams <- tbl(db_con, I("nba.teams_vw")) |>
  select(team_slug, team_id) |>
  as_tibble() |>
  mutate(team_id = as.integer(team_id)) |>
  arrange(team_slug) |>
  nest_by(team_slug, .key = "team_id") |>
  mutate(team_id = team_id$team_id) |>
  deframe()

# Team roster ------------------------------------------------------------

df_nba_roster <- tbl(db_con, I("nba.team_roster_vw")) |>
  filter(season == cur_season) |>
  # filter(entry_date < cur_date | is.na(entry_date)) |> # for testing purposes
  as_tibble() |>
  mutate(across(ends_with("_id"), \(x) as.integer(x)))


# Player rolling stats ---------------------------------------------------

dfs_rolling_stats <- df_nba_player_box_score |>
  arrange(game_date) |>
  filter(game_date < cur_date, !is.na(player_id)) |>
  mutate(across(all_of(player_stat_cols), \(x) coalesce(x, 0))) |>
  select(-year_season_type) |>
  (\(df_t) {
    map(set_names(c(7, 15, 30)), \(window) {
      df_t |>
        mutate(
          across(any_of(player_stat_cols), \(x) {
            slider::slide_period_dbl(x, game_date, "day", ~ median(.x, na.rm = TRUE), .before = window, .after = -1)
          }),
          .by = player_id
        ) |>
        mutate(across(any_of(player_stat_cols), \(x) coalesce(x, 0)))
    })
  })() |>
  map(\(df_t) {
    df_t |>
      bind_rows(
        df_nba_schedule |>
          filter(game_date > cur_date - days(1)) |>
          left_join(
            df_nba_roster,
            by = join_by(
              season,
              team == team_slug,
              game_date >= entry_date,
              game_date < exit_date
            ),
            relationship = "many-to-many"
          ) |>
          select(
            player_id,
            espn_id,
            yahoo_id,
            player_name,
            team,
            game_date,
            dow,
            opponent,
            game_id,
            season,
            season_type,
            home,
            starts_with("inj_")
          ) |>
          left_join(
            slice_max(df_t, order_by = game_date, by = player_id) |>
              select(player_id, min:last_col()),
            by = join_by(player_id),
            relationship = "many-to-many"
          )
      ) |>
      mutate(inj_status = if_else(game_date < cur_date, coalesce(inj_status, "Available"), inj_status)) |>
      arrange(game_date) |>
      group_by(player_id) |>
      fill(inj_status, .direction = "down") |>
      ungroup()
  }) |>
  map(\(df_t) {
    bind_rows(
      df_t,
      slice_max(df_t, game_date, by = player_id) |>
        mutate(
          season_type = "Post Fantasy",
          game_id = NA,
          game_date = as.Date("2999-01-01"),
          dow = NA,
          opponent = NA
        )
    )
  })


# Recent injuries (shared) -----------------------------------------------

min_inj_date <- as.Date(cur_date - days(30))
df_ns_injuries <-
  tbl(db_con, I("nba.injuries")) |>
  filter(game_date >= min_inj_date, status == "Out") |>
  as_tibble() |>
  mutate(
    across(ends_with("_id"), \(x) as.integer(x)),
    opponent = str_remove(matchup, "@"),
    opponent = str_remove(opponent, team_slug),
    opponent = str_squish(opponent)
  ) |>
  left_join(
    df_nba_roster |>
      select(nba_id = player_id, salary) |>
      distinct(),
    by = join_by(nba_id)
  ) |>
  select(team = team_slug, opponent, game_date, player_name, salary) |>
  arrange(desc(game_date), desc(salary)) |>
  summarise(player_names = paste(player_name, collapse = ", "), .by = c(team, opponent, game_date))

ls_injuries <-
  map(set_names(names(dfs_rolling_stats)), \(x) {
    df_ns_injuries |>
      filter(game_date >= max(game_date) - days(x)) |>
      nest_by(team, .keep = TRUE) |>
      deframe()
  })


# Player game log (shared) -----------------------------------------------

ls_player_game_log <-
  df_nba_player_box_score |>
  filter(between(game_date, max(game_date) - ddays(30), max(game_date) - ddays(1))) |>
  select(player_id, game_date, opponent, any_of(player_stat_cols)) |>
  arrange(desc(game_date)) |>
  nest_by(player_id) |>
  deframe()


# Write data -------------------------------------------------------------

# Generation-only shared objects are cached for _generate_league.R so the base
# layer is built once and reused by every league container. The runtime shared
# objects are written to data/ by the league layer, keeping per-league builds
# self-contained.
cache_dir <- here::here("data-raw", "cache")
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
save(
  df_nba_player_box_score,
  df_nba_schedule,
  df_nba_season_segments,
  df_nba_roster,
  dfs_rolling_stats,
  ls_nba_teams,
  ls_injuries,
  ls_player_game_log,
  file = file.path(cache_dir, "base.rda"),
  compress = "xz"
)
