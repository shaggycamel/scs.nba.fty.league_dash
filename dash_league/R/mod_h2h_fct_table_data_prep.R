grey_intervals_from_stints <- function(start, end, matchup_start, latest_assigned_date) {
  still_rostered <- isTRUE(max(end, na.rm = TRUE) == latest_assigned_date)

  grey_start <- c(matchup_start, end + 1)
  grey_end <- c(start - 1, if (still_rostered) as.Date(NA) else as.Date("3000-01-01"))

  tibble(start = grey_start, end = grey_end) |>
    filter(!is.na(start), !is.na(end), start <= end)
}


empty_grey <- function() {
  tibble(
    competitor_id = integer(),
    player_id = integer(),
    grey_intervals = list()
  )
}


alter_grey_intervals <- function(input, df_base, rv_carry_thru, rv_alter_team) {
  applies <- isTRUE(
    as.integer(input$matchup) >= rv_carry_thru$cur_matchup_period
  )

  added <- rv_alter_team |>
    keep(\(x) x$action == "add" && as.Date(x$action_date) >= cur_date) |>
    map_int("player_id")

  ex <- rv_alter_team |>
    keep(\(x) x$action == "ex") |>
    map(\(x) {
      tibble(
        player_id = as.integer(x$player_id),
        action_date = as.Date(x$action_date)
      )
    }) |>
    list_rbind()

  if (!applies || nrow(ex) == 0) {
    return(empty_grey())
  }

  ex <- ex |>
    filter(
      !player_id %in% added,
      action_date >= cur_date
    )

  if (nrow(ex) == 0) {
    return(empty_grey())
  }

  matchup_start <- min(df_base$matchup_start, na.rm = TRUE)

  ex |>
    mutate(
      competitor_id = as.integer(rv_carry_thru$competitor_id),
      start = pmax(action_date, matchup_start)
    ) |>
    summarise(
      start = min(start),
      .by = c(competitor_id, player_id)
    ) |>
    mutate(
      grey_intervals = map(
        start,
        \(s) tibble(start = s, end = as.Date("3000-01-01"))
      )
    ) |>
    select(competitor_id, player_id, grey_intervals)
}


grey_player_data_prep <- function(input, df_base, rv_carry_thru, opponent, rv_alter_team) {
  roster <- pluck(dfs_fty_roster, as.character(rv_carry_thru$league_id)) |>
    filter(
      competitor_id %in% c(rv_carry_thru$competitor_id, opponent()$id),
      matchup_period == as.integer(input$matchup),
      assigned_date >= matchup_start,
      assigned_date <= matchup_end
    )

  roster_grey <- if (nrow(roster) == 0) {
    empty_grey()
  } else {
    observed <- roster |>
      distinct(competitor_id, assigned_date) |>
      arrange(competitor_id, assigned_date) |>
      mutate(snapshot = seq_along(assigned_date), .by = competitor_id)

    latest <- observed |>
      summarise(latest_assigned_date = max(assigned_date), .by = competitor_id)

    roster |>
      distinct(competitor_id, player_id, assigned_date, matchup_start) |>
      inner_join(observed, by = join_by(competitor_id, assigned_date)) |>
      arrange(competitor_id, player_id, snapshot) |>
      mutate(
        new_stint = c(TRUE, diff(snapshot) > 1),
        .by = c(competitor_id, player_id)
      ) |>
      mutate(stint = cumsum(new_stint), .by = c(competitor_id, player_id)) |>
      summarise(
        start = min(assigned_date),
        end = max(assigned_date),
        matchup_start = min(matchup_start, na.rm = TRUE),
        .by = c(competitor_id, player_id, stint)
      ) |>
      left_join(latest, by = join_by(competitor_id)) |>
      arrange(competitor_id, player_id, start) |>
      summarise(
        grey_intervals = list(
          grey_intervals_from_stints(
            start,
            end,
            matchup_start[1],
            latest_assigned_date[1]
          )
        ),
        .by = c(competitor_id, player_id)
      ) |>
      filter(map_int(grey_intervals, nrow) > 0)
  }

  bind_rows(
    roster_grey,
    alter_grey_intervals(input, df_base, rv_carry_thru, rv_alter_team)
  ) |>
    summarise(
      grey_intervals = list(distinct(bind_rows(grey_intervals))),
      .by = c(competitor_id, player_id)
    ) |>
    inner_join(
      distinct(df_base, competitor_id, player_id),
      by = join_by(competitor_id, player_id)
    )
}


table_data_prep <- function(df_base, rv_carry_thru, df_grey_player, pin_date, post_matchup_days = 2) {
  df_wide <- df_base |>
    arrange(game_date) |>
    select(competitor, competitor_id, player_team, player_id, player_name, inj_status, fmt_date, scheduled_to_play) |>
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
  # matches no columns. The matchup end bounds the total, so the post-matchup
  # days that render after games_remaining never count towards it.
  col_dates <- col_dates_from_labels(names(df_wide), matchup_start)
  remaining_cols <- pin_columns(
    col_dates,
    pin_date,
    matchup_start,
    max(df_base$matchup_end, na.rm = TRUE),
    "+"
  )

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
    left_join(df_grey_player, by = join_by(player_id, competitor_id))
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
  matchup_start <- min(df_base$matchup_start, na.rm = TRUE)
  col_dates <- col_dates_from_labels(names(df_sum), matchup_start)
  remaining_cols <- pin_columns(
    col_dates,
    pin_date,
    matchup_start,
    max(df_base$matchup_end, na.rm = TRUE),
    "+"
  )

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
    mutate(grey_intervals = vector("list", length(player_team)))
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
