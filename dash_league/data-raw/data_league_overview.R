# League overview dataframes ---------------------------------------------

dfs_league_overview <-
  df_fty_box_score |>
  left_join(
    df_fty_box_score |>
      mutate(
        across(
          any_of(df_fty_cats$nba_category),
          \(x) if (cur_column() %in% lower_is_better_cats) percent_rank(-x) else percent_rank(x),
          .names = "{.col}-perc_rank"
        ),
        .by = c(league_id, matchup)
      ) |>
      rename_with(
        \(x) paste0(x, "-value"),
        .cols = any_of(df_fty_cats$nba_category)
      ) |>
      pivot_longer(
        matches(paste(df_fty_cats$nba_category, collapse = "|")),
        names_to = c("category", ".value"),
        names_sep = "-"
      ) |>
      inner_join(
        filter(df_fty_cats, category_role == "scored") |>
          select(league_id, nba_category),
        by = join_by(league_id, category == nba_category)
      ) |>
      arrange(category) |>
      mutate(all_cat_text = paste0(category, ": ", round(value, 2), " (", round(perc_rank, 2), ")")) |>
      summarise(
        all_cat = sum(perc_rank, na.rm = TRUE),
        all_cat_text = paste(all_cat_text, collapse = "\n"),
        .by = c(league_id, competitor_id, matchup)
      ) |>
      mutate(all_cat_text = paste("<b>Total -", round(all_cat, 2), "</b>", "\n", all_cat_text)),
    by = join_by(league_id, competitor_id, matchup)
  ) |>
  mutate(
    across(
      any_of(c(df_fty_cats$nba_category, "matchup")),
      \(x) lead(x, order_by = matchup),
      .names = "{.col}_lead"
    ),
    .by = c(league_id, competitor_id)
  ) |>
  mutate(
    across(
      any_of(df_fty_cats$nba_category),
      \(x) if (cur_column() %in% lower_is_better_cats) rank(x) else rank(-x),
      .names = "{.col}_rank"
    ),
    .by = c(league_id, matchup)
  ) |>
  mutate(
    across(
      any_of(str_c(df_fty_cats$nba_category, "_rank")),
      \(x) lead(x, order_by = matchup),
      .names = "{.col}_lead"
    ),
    .by = c(league_id, competitor_id)
  ) |>
  mutate(across(where(is.numeric), \(x) as.double(replace_na(x, 0)))) |>
  (\(df_tmp) {
    filter(df_tmp, matchup < max(matchup), .by = league_id) |>
      group_by(league_id, competitor_id, matchup) |>
      group_modify(.keep = TRUE, \(df_t, ...) {
        x <- seq(-5, 5, 0.3)
        df_ls <- list()

        # To handle when df is empty, ie - start of season
        if (nrow(df_t) > 0) {
          for (stat in intersect(df_fty_cats$nba_category, colnames(df_t))) {
            matchup_sigmoid <- x
            if (df_t[[stat]] > df_t[[str_c(stat, "_lead")]]) {
              matchup_sigmoid <- rev(matchup_sigmoid)
            }
            stat_sigmoid <- scales::rescale(
              sigmoid(matchup_sigmoid),
              to = c(df_t[[stat]], df_t[[str_c(stat, "_lead")]])
            )
            stat_rank_sigmoid <- scales::rescale(
              sigmoid(matchup_sigmoid),
              to = c(df_t[[str_c(stat, "_rank")]], df_t[[str_c(stat, "_rank_lead")]])
            )
            matchup_sigmoid <- scales::rescale(matchup_sigmoid, to = c(df_t$matchup, df_t$matchup_lead))

            df_ls <- df_ls |>
              append(list(tibble(
                matchup_sigmoid = matchup_sigmoid,
                stat = stat,
                sigmoid = stat_sigmoid,
                rank_sigmoid = as.double(stat_rank_sigmoid)
              )))
          }
        }

        if (length(df_ls) == 0) {
          tibble(
            matchup_sigmoid = double(),
            stat = character(),
            sigmoid = double(),
            rank_sigmoid = double()
          )
        } else {
          bind_rows(df_ls)
        }
      }) |>
      ungroup() |>
      filter(!(as.integer(matchup_sigmoid) == matchup_sigmoid & matchup != matchup_sigmoid)) |>
      pivot_wider(names_from = stat, values_from = c(sigmoid, rank_sigmoid)) |>
      rename_with(\(x) str_remove(x, "sigmoid_"), .cols = starts_with("sigmoid_")) |>
      rename_with(\(x) str_c(str_remove(x, "rank_sigmoid_"), "_rank"), .cols = starts_with("rank_sigmoid_")) |>
      bind_rows(
        select(df_tmp, -all_cat_text) |>
          filter(matchup == max(matchup), .by = league_id)
      ) |>
      left_join(
        select(df_tmp, league_id, competitor_id, matchup, all_cat_text),
        by = join_by(league_id, competitor_id, matchup)
      )
  })() |>
  mutate(matchup_sigmoid = if_else(is.na(matchup_sigmoid), matchup, matchup_sigmoid)) |>
  (\(df) {
    # Scored categories plus the derived z-scores; components and all_cat excluded
    cols <- df_fty_cats |>
      filter(category_role != "component", nba_category != "all_cat") |>
      pull(nba_category) |>
      unique() |>
      intersect(colnames(df))

    bind_cols(
      df,
      map(set_names(cols), \(x) {
        paste0(x, ": ", round(pull(df, x), 2), " (", round(pull(df, !!sym(paste0(x, "_rank"))), 2), ")")
      }) |>
        bind_cols() |>
        rename_with(\(x) paste0(x, "_text"))
    )
  })() |>
  left_join(
    select(df_fty_base, league_id, competitor_id, competitor_name),
    by = join_by(league_id, competitor_id)
  ) |>
  mutate(
    across(ends_with("_text"), \(x) paste0("<b>", matchup, " - ", competitor_name, "</b>", "<br>", x)),
    .by = c(league_id, matchup, competitor_id)
  ) |>
  select(-ends_with("_lead")) |>
  nest_by(league_id) |>
  deframe()


# League standings -------------------------------------------------------

# Standings are ranked differently per league type:
#   H2H_CATEGORY        - by category record (every scored category is a W/L/T)
#   H2H_MOST_CATEGORIES - by matchup record (most categories won that week)
#   H2H_POINTS          - by matchup record (highest fantasy points that week)
# Only completed matchups count, so an in-progress week is excluded.

dfs_fty_standings <-
  tbl(db_con, I("fty.matchup_result")) |>
  filter(season == cur_season) |>
  as_tibble() |>
  filter(league_id %in% target_leagues) |>
  mutate(across(c(ends_with("_id"), matchup, cat_won, cat_lost, cat_tied), \(x) as.integer(x))) |>
  left_join(
    dfs_fty_schedule |>
      list_rbind(names_to = "league_id") |>
      mutate(league_id = as.integer(league_id)) |>
      distinct(league_id, matchup_period, matchup_end),
    by = join_by(league_id, matchup == matchup_period)
  ) |>
  filter(matchup_end < cur_date) |>
  left_join(
    select(df_fty_base, league_id, competitor_id, competitor_name),
    by = join_by(league_id, competitor_id)
  ) |>
  left_join(
    distinct(df_fty_cats, league_id, scoring_type),
    by = join_by(league_id)
  ) |>
  group_by(league_id) |>
  group_modify(\(df_lg, ...) {
    scoring_type <- unique(df_lg$scoring_type)

    if (nrow(df_lg) == 0 || length(scoring_type) == 0) {
      return(tibble(
        competitor_id = integer(),
        competitor_name = character(),
        wins = integer(),
        losses = integer(),
        ties = integer(),
        pct = double(),
        rank = integer()
      ))
    }

    df_standings <- if (scoring_type == "H2H_CATEGORY") {
      summarise(
        df_lg,
        wins = sum(cat_won, na.rm = TRUE),
        losses = sum(cat_lost, na.rm = TRUE),
        ties = sum(cat_tied, na.rm = TRUE),
        .by = c(competitor_id, competitor_name)
      )
    } else if (scoring_type == "H2H_POINTS") {
      summarise(
        df_lg,
        wins = sum(result == "W", na.rm = TRUE),
        losses = sum(result == "L", na.rm = TRUE),
        ties = sum(result == "T", na.rm = TRUE),
        points_for = sum(score, na.rm = TRUE),
        points_against = sum(opponent_score, na.rm = TRUE),
        .by = c(competitor_id, competitor_name)
      )
    } else {
      # H2H_MOST_CATEGORIES: matchups are won by category count, so
      # points-for/against would not be meaningful and are left off.
      summarise(
        df_lg,
        wins = sum(result == "W", na.rm = TRUE),
        losses = sum(result == "L", na.rm = TRUE),
        ties = sum(result == "T", na.rm = TRUE),
        .by = c(competitor_id, competitor_name)
      )
    }

    df_standings |>
      mutate(pct = (wins + 0.5 * ties) / (wins + losses + ties)) |>
      arrange(desc(wins), losses, desc(pct)) |>
      mutate(rank = row_number()) |>
      select(rank, competitor_id, competitor_name, wins, losses, ties, pct, any_of(c("points_for", "points_against")))
  }) |>
  ungroup() |>
  nest_by(league_id) |>
  deframe()


# Season category totals -------------------------------------------------

# Season-accumulated per-category totals and ranks, backing the standings
# drill-down. Only the categories a league actually scores are kept. Ratio
# categories (fg_pct/ft_pct) are rebuilt from their components so the season
# value is a true ratio, not a sum of weekly percentages. Completed matchups
# only, matching dfs_fty_standings.

completed_matchups <-
  dfs_fty_schedule |>
  list_rbind(names_to = "league_id") |>
  mutate(league_id = as.integer(league_id)) |>
  filter(matchup_end < cur_date) |>
  distinct(league_id, matchup_period) |>
  rename(matchup = matchup_period)

# Weighted category points a league actually scored (value * its weight). NA for
# leagues that score by category: their leagues_categories rows carry no points.
df_fty_box_score_points <-
  df_fty_box_score_long |>
  inner_join(completed_matchups, by = join_by(league_id, matchup)) |>
  summarise(
    fantasy_points = if (all(is.na(fantasy_points))) NA_real_ else sum(fantasy_points, na.rm = TRUE),
    .by = c(league_id, competitor_id, category)
  )

dfs_fty_standings_cats <-
  map(set_names(target_leagues), \(l_id) {
    df_bs <- df_fty_box_score |>
      filter(league_id == l_id) |>
      inner_join(filter(completed_matchups, league_id == l_id), by = join_by(league_id, matchup))

    df_fty_cats |>
      filter(league_id == l_id, category_role == "scored") |>
      arrange(display_order) |>
      (\(df_cats_lg) {
        map(set_names(df_cats_lg$nba_category), \(cat) {
          meta <- filter(df_cats_lg, nba_category == cat)

          value <- if (is.na(meta$numerator)) {
            summarise(df_bs, value = sum(.data[[cat]], na.rm = TRUE), .by = competitor_id)
          } else {
            summarise(
              df_bs,
              value = sum(.data[[meta$numerator]], na.rm = TRUE) / sum(.data[[meta$denominator]], na.rm = TRUE),
              .by = competitor_id
            )
          }

          value |>
            left_join(
              filter(df_fty_box_score_points, league_id == l_id, category == cat) |>
                select(competitor_id, fantasy_points),
              by = join_by(competitor_id)
            ) |>
            mutate(
              league_id = l_id,
              category = cat,
              fmt_category = meta$fmt_category,
              display_order = meta$display_order,
              is_ratio = meta$is_ratio,
              higher_is_better = meta$higher_is_better
            )
        }) |>
          list_rbind()
      })()
  }) |>
  list_rbind() |>
  mutate(
    rank = if_else(higher_is_better, rank(-value), rank(value)),
    .by = c(league_id, category)
  ) |>
  select(competitor_id, category, fmt_category, display_order, is_ratio, value, fantasy_points, rank, league_id) |>
  arrange(league_id, competitor_id, display_order) |>
  group_by(league_id) |>
  nest() |>
  deframe()


# Write data -------------------------------------------------------------

usethis::use_data(dfs_league_overview, dfs_fty_standings, dfs_fty_standings_cats, overwrite = TRUE)
