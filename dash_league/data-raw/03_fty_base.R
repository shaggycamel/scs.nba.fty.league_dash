# League selection -------------------------------------------------------
# Fantasy data is league-scoped and customer-agnostic. When LEAGUE_ID is set
# (comma-separated ids) only those leagues are generated, for a per-league
# container build; otherwise every league with data for the season is used.

df_fty_base_all <-
  tbl(db_con, I("fty.base_vw")) |>
  filter(season == cur_season) |>
  as_tibble()

target_leagues <- Sys.getenv("LEAGUE_ID", unset = "")
target_leagues <- if (nzchar(target_leagues)) {
  as.integer(strsplit(target_leagues, ",")[[1]])
} else {
  unique(df_fty_base_all$league_id)
}


# Fty base ---------------------------------------------------------------

df_fty_base <-
  df_fty_base_all |>
  filter(league_id %in% target_leagues) |>
  arrange(str_to_lower(league_name), str_to_lower(competitor_name)) |>
  mutate(across(ends_with("_id"), \(x) as.integer(x)))


# Fty categories ---------------------------------------------------------

# category_role tells you what a category is for:
#   scored    - what the league actually plays
#   component - fgm/fga/ftm/fta, needed to build fg_pct/ft_pct and the z-scores even
#               when the league does not score them
#   derived   - all_cat/fg_z/ft_z, calculated here rather than stored
df_fty_cats <-
  tbl(db_con, I("fty.categories_vw")) |>
  filter(season == cur_season) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(across(ends_with("_id"), \(x) as.integer(x)))

# Categories a league plays, and those where a low value is the good outcome
scored_cats <- unique(pull(filter(df_fty_cats, category_role == "scored"), nba_category))
lower_is_better_cats <- unique(pull(filter(df_fty_cats, !higher_is_better), nba_category))


# Fty schedule -----------------------------------------------------------

dfs_fty_schedule <-
  tbl(db_con, I("fty.league_schedule_vw")) |>
  filter(season == cur_season) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(
    across(matches("_id$|_period$"), \(x) as.integer(x)),
    matchup = str_c(matchup_period, " (", matchup_start, ")")
  ) |>
  (\(df) {
    bind_rows(
      df,
      distinct(df, league_id, season, platform, competitor_id) |>
        left_join(
          summarise(df, matchup_start = max(matchup_end) + ddays(1), .by = c(season, platform, league_id)) |>
            mutate(matchup_period = 99, matchup_end = as.Date("2999-01-01"), matchup = "Post Fantasy")
        )
    )
  })() |>
  nest_by(league_id) |>
  deframe()


# Fty roster -------------------------------------------------------------

dfs_fty_roster <-
  tbl(db_con, I("fty.roster_schedule_vw")) |>
  filter(season == cur_season) |>
  # filter(assigned_date < cur_date) |> # for testing purposes
  select(-c(competitor_name, opponent_name)) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(across(matches("_id$|_period$"), \(x) as.integer(x))) |>
  mutate(dow = wday(assigned_date, week_start = 1), .after = assigned_date) |>
  left_join(
    select(df_nba_season_segments, starts_with("season"), begin_date, end_date),
    by = join_by(season, assigned_date >= begin_date, assigned_date <= end_date)
  ) |>
  filter(season_type == "Regular Season") |>
  nest_by(league_id) |>
  deframe()

# Fantasy Box Scores -----------------------------------------------------

# Long form keeps the weighted per-category points; the wide form below keeps
# the raw values the category views are built on.
df_fty_box_score_long <-
  tbl(db_con, I("fty.matchup_box_score_vw")) |>
  filter(season == cur_season, league_id %in% target_leagues) |>
  select(league_id, competitor_id, matchup, category, value, fantasy_points) |>
  as_tibble() |>
  mutate(across(c(ends_with("_id"), matchup), \(x) as.integer(x)))

df_fty_box_score <-
  df_fty_box_score_long |>
  select(-fantasy_points) |>
  pivot_wider(
    id_cols = c(league_id, competitor_id, matchup),
    names_from = category,
    values_from = value
  ) |>
  group_by(league_id, matchup) |>
  calc_z_pcts() |>
  ungroup()


# Free Agents ------------------------------------------------------------

dfs_fty_free_agents <-
  tbl(db_con, I("fty.free_agents_vw")) |>
  filter(season == cur_season) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(across(ends_with("_id"), \(x) as.integer(x))) |>
  nest_by(league_id) |>
  deframe()


# Recent Avtivity --------------------------------------------------------

dfs_fty_recent_activity <-
  tbl(db_con, I("fty.recent_activity_vw")) |>
  filter(season == cur_season) |>
  select(league_id, competitor_id, competitor_name, player, action, timestamp) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(across(ends_with("_id"), \(x) as.integer(x))) |>
  arrange(desc(timestamp)) |>
  nest_by(league_id) |>
  deframe()


# League categories ------------------------------------------------------

ls_lo_lg_cats <-
  map(set_names(unique(df_fty_cats$league_id)), \(x) {
    df_lg <- filter(df_fty_cats, league_id == x) |> arrange(display_order)

    list(
      "Overall" = c("All Categories" = "all_cat"),
      "Categories" = df_lg |>
        filter(category_role == "scored") |>
        select(fmt_category, nba_category) |>
        deframe(),
      "Z Scores" = df_lg |>
        filter(category_role == "derived", str_detect(nba_category, "_z$")) |>
        select(fmt_category, nba_category) |>
        deframe()
    )
  })


# Category weights -------------------------------------------------------

df_fty_cat_weights <-
  df_fty_cats |>
  filter(category_role == "scored") |>
  select(league_id, nba_category, fmt_category, display_order, higher_is_better, points, scoring_type) |>
  arrange(league_id, display_order, nba_category)


# Conversion list --------------------------------------------------------

ls_fty_lookup <- list(
  "lg_name_to_id" = as.list(deframe(distinct(df_fty_base, league_name, league_id))),
  "lg_id_to_name" = as.list(deframe(distinct(df_fty_base, league_id, league_name))),
  "lg_id_to_platform" = as.list(deframe(distinct(df_fty_base, league_id, platform))),
  "cp_id_to_name" = select(df_fty_base, league_id, competitor_id, competitor_name) |>
    nest_by(league_id) |>
    mutate(data = list(as.list(deframe(data)))) |>
    deframe(),
  "cp_name_to_id" = select(df_fty_base, league_id, competitor_name, competitor_id) |>
    nest_by(league_id) |>
    mutate(data = list(as.list(deframe(data)))) |>
    deframe()
)

usethis::use_data(
  df_fty_base,
  dfs_fty_schedule,
  dfs_fty_roster,
  dfs_fty_recent_activity,
  ls_lo_lg_cats,
  df_fty_cat_weights,
  ls_fty_lookup,
  overwrite = TRUE
)
