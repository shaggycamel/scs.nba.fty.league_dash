grey_player_data_prep <- function(input, df_base, rv_carry_thru, opponent) {
  # past roster
  df_base |>
    filter(tense == "past") |>
    summarise(
      min_grey_date = min(game_date),
      max_grey_date = max(game_date),
      .by = player_id
    ) |>
    inner_join(
      # Current Roster
      pluck(dfs_fty_roster, as.character(rv_carry_thru$league_id)) |>
        filter(
          competitor_id %in% c(rv_carry_thru$competitor_id, opponent()$id),
          matchup_period == as.integer(input$matchup)
        ) |>
        mutate(max_assigned_date = max(assigned_date)) |>
        filter(
          min(assigned_date) != matchup_start |
            max(assigned_date) != max_assigned_date,
          .by = player_id
        ) |>
        distinct(player_id, matchup_start, max_assigned_date),
      by = join_by(player_id)
    ) |>
    mutate(
      min_grey_date = if_else(
        min_grey_date == matchup_start,
        NA_Date_,
        min_grey_date
      ),
      max_grey_date = if_else(
        between(max_grey_date, max_assigned_date - 1, max_assigned_date),
        NA_Date_,
        max_grey_date
      )
    ) |>
    select(-c(matchup_start, max_assigned_date))
}


table_data_prep <- function(df_base, rv_carry_thru, df_grey_player, pin_date, post_matchup_days = 2) {
  df_wide <- df_base |>
    arrange(game_date) |>
    select(competitor, player_team, player_id, player_name, inj_status, fmt_date, scheduled_to_play) |>
    distinct() |>
    mutate(
      scheduled_to_play = as.character(replace_na(scheduled_to_play, 0)),
      scheduled_to_play = if_else(
        inj_status == "Out",
        str_c(scheduled_to_play, "*"),
        scheduled_to_play,
        missing = scheduled_to_play
      )
    ) |>
    select(-inj_status) |>
    pivot_wider(
      names_from = fmt_date,
      values_from = scheduled_to_play,
      values_fill = "0"
    ) |>
    select(-starts_with("NA"))

  # Fill before games_remaining is added, so the new columns sort in among the
  # dates rather than landing after it.
  matchup_start <- min(df_base$matchup_start, na.rm = TRUE)
  df_wide <- fill_missing_days(
    df_wide,
    matchup_start,
    max(df_base$matchup_end, na.rm = TRUE),
    fill = "0",
    post_matchup_days = post_matchup_days
  )

  # Select the pinned day onward by name. A pin_date outside the matchup - which
  # happens for a flush while the date picker catches up with df_base - simply
  # matches no columns.
  col_dates <- col_dates_from_labels(names(df_wide), matchup_start)
  remaining_cols <- names(col_dates)[col_dates >= pin_date]

  df_wide |>
    rowwise() |>
    mutate(
      games_remaining = if (cur_date > unique(na.omit(df_base$matchup_end))) {
        0
      } else {
        sum(as.numeric(str_remove(c_across(all_of(remaining_cols)), "\\*")), na.rm = TRUE)
      },
      .before = if (all(is.na(df_base$matchup_end_plus))) last_col() else last_col(2)
    ) |>
    ungroup() |>
    left_join(df_grey_player, by = join_by(player_id))
}

table_sum_data_prep <- function(df_tbl, df_base, pin_date) {
  df_sum <- df_tbl |>
    summarise(
      across(
        contains("/"),
        \(x) sum(as.numeric(str_remove(x, "\\*")) * !str_detect(x, "\\*"), na.rm = TRUE)
      ),
      .by = competitor
    ) |>
    arrange(desc(competitor)) |>
    rename(player_team = competitor) |>
    mutate(player_name = NA, .after = player_team)

  # See table_data_prep(). df_tbl has already been filled, so its date columns
  # carry through the summarise and no further filling is needed here.
  col_dates <- col_dates_from_labels(names(df_sum), min(df_base$matchup_start, na.rm = TRUE))
  remaining_cols <- names(col_dates)[col_dates >= pin_date]

  df_sum |>
    rowwise() |>
    mutate(
      games_remaining = if (cur_date > unique(na.omit(df_base$matchup_end))) {
        0
      } else {
        sum(as.numeric(str_remove(c_across(all_of(remaining_cols)), "\\*")), na.rm = TRUE)
      },
      .before = if (all(is.na(df_base$matchup_end_plus))) last_col() else last_col(2)
    ) |>
    ungroup() |>
    mutate(min_grey_date = NA_Date_, max_grey_date = NA_Date_)
}


# The end-of-season matchup has no game schedule. Show each competitor's roster
# from its latest available assignment date instead of building date columns.
postseason_roster_data_prep <- function(df_roster, selected_competitor_id) {
  df_roster |>
    ungroup() |>
    filter(competitor_id == as.integer(selected_competitor_id)) |>
    slice_max(assigned_date, n = 1, with_ties = TRUE) |>
    distinct(player_id, player_name, player_team) |>
    arrange(player_name)
}
