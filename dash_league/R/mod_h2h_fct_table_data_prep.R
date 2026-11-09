intervals_from_runs <- function(flag, snapshot_dates, matchup_start, still_rostered) {
  if (!any(flag)) {
    return(tibble(start = as.Date(character()), end = as.Date(character())))
  }

  run_id <- cumsum(flag & c(TRUE, !flag[-length(flag)]))

  tibble(snapshot = seq_along(flag), flag = flag, run_id = if_else(flag, run_id, NA_integer_)) |>
    filter(flag) |>
    summarise(first = min(snapshot), last = max(snapshot), .by = run_id) |>
    arrange(first) |>
    mutate(
      start = if_else(first == 1L, matchup_start, snapshot_dates[first]),
      trailing = if (still_rostered) snapshot_dates[last] else as.Date("3000-01-01"),
      end = if_else(
        last < length(snapshot_dates),
        snapshot_dates[last + 1L] - 1,
        trailing
      )
    ) |>
    filter(start <= end) |>
    select(start, end)
}


empty_grey <- function() {
  tibble(
    competitor_id = integer(),
    player_id = integer(),
    grey_intervals = list()
  )
}


alter_applies <- function(input, rv_carry_thru) {
  isTRUE(as.integer(input$matchup) >= rv_carry_thru$cur_matchup_period)
}


alter_grey_intervals <- function(input, df_base, rv_carry_thru, rv_alter_team) {
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

  if (!alter_applies(input, rv_carry_thru) || nrow(ex) == 0) {
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


empty_adds <- function() {
  tibble(player_id = integer(), action_date = as.Date(character()))
}


alter_team_adds <- function(rv_alter_team) {
  adds <- rv_alter_team |>
    keep(\(x) x$action == "add" && as.Date(x$action_date) >= cur_date) |>
    map(\(x) {
      tibble(
        player_id = as.integer(x$player_id),
        action_date = as.Date(x$action_date)
      )
    }) |>
    list_rbind()

  if (is.null(adds) || nrow(adds) == 0) {
    return(empty_adds())
  }

  adds |>
    summarise(action_date = min(action_date), .by = player_id)
}


add_grey_intervals <- function(input, df_base, rv_carry_thru, rv_alter_team, roster) {
  if (!alter_applies(input, rv_carry_thru)) {
    return(empty_grey())
  }

  add <- alter_team_adds(rv_alter_team)

  if (nrow(add) == 0) {
    return(empty_grey())
  }

  cp_id <- as.integer(rv_carry_thru$competitor_id)

  rostered_here <- roster |>
    filter(competitor_id == !!cp_id) |>
    distinct(player_id) |>
    pull(player_id)

  matchup_start <- min(df_base$matchup_start, na.rm = TRUE)

  add |>
    filter(!player_id %in% rostered_here) |>
    mutate(end = action_date - 1) |>
    filter(end >= matchup_start) |>
    mutate(
      competitor_id = cp_id,
      grey_intervals = map(
        end,
        \(e) tibble(start = matchup_start, end = e)
      )
    ) |>
    select(competitor_id, player_id, grey_intervals)
}


# A player added from another team leaves that team on the action date.
add_owner_grey_intervals <- function(input, df_base, rv_carry_thru, add) {
  if (!alter_applies(input, rv_carry_thru) || nrow(add) == 0) {
    return(empty_grey())
  }

  cp_id <- as.integer(rv_carry_thru$competitor_id)

  shown_opponents <- df_base |>
    filter(competitor_id != cp_id) |>
    distinct(competitor_id)

  alter_team_add_owner(as.character(rv_carry_thru$league_id), add) |>
    inner_join(shown_opponents, by = join_by(competitor_id)) |>
    inner_join(add, by = join_by(player_id)) |>
    mutate(
      grey_intervals = map(
        action_date,
        \(d) tibble(start = d, end = as.Date("3000-01-01"))
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
    matchup_start <- min(roster$matchup_start, na.rm = TRUE)

    observed <- roster |>
      distinct(competitor_id, assigned_date) |>
      arrange(competitor_id, assigned_date) |>
      mutate(snapshot = seq_along(assigned_date), .by = competitor_id)

    roster_snapshots <- roster |>
      distinct(competitor_id, player_id, assigned_date) |>
      inner_join(observed, by = join_by(competitor_id, assigned_date)) |>
      mutate(rostered = TRUE) |>
      select(competitor_id, player_id, snapshot, rostered)

    roster_snapshots |>
      distinct(competitor_id, player_id) |>
      inner_join(observed, by = join_by(competitor_id), relationship = "many-to-many") |>
      left_join(roster_snapshots, by = join_by(competitor_id, player_id, snapshot)) |>
      mutate(rostered = coalesce(rostered, FALSE)) |>
      arrange(competitor_id, player_id, snapshot) |>
      summarise(
        grey_intervals = list(
          intervals_from_runs(!rostered, assigned_date, matchup_start, tail(rostered, 1))
        ),
        .by = c(competitor_id, player_id)
      ) |>
      filter(map_int(grey_intervals, nrow) > 0)
  }

  add <- if (alter_applies(input, rv_carry_thru)) {
    alter_team_adds(rv_alter_team)
  } else {
    empty_adds()
  }

  bind_rows(
    roster_grey,
    alter_grey_intervals(input, df_base, rv_carry_thru, rv_alter_team),
    add_grey_intervals(input, df_base, rv_carry_thru, rv_alter_team, roster),
    add_owner_grey_intervals(input, df_base, rv_carry_thru, add)
  ) |>
    summarise(
      grey_intervals = list(distinct(bind_rows(grey_intervals))),
      .by = c(competitor_id, player_id)
    ) |>
    (\(df) {
      if (nrow(add) == 0) {
        return(df)
      }

      df |>
        left_join(
          add |>
            mutate(competitor_id = as.integer(rv_carry_thru$competitor_id)),
          by = join_by(competitor_id, player_id)
        ) |>
        mutate(
          grey_intervals = map2(grey_intervals, action_date, \(iv, d) {
            if (is.na(d)) {
              iv
            } else {
              iv |>
                mutate(end = pmin(end, d - 1)) |>
                filter(start <= end)
            }
          })
        ) |>
        select(-action_date)
    })() |>
    inner_join(
      distinct(df_base, competitor_id, player_id),
      by = join_by(competitor_id, player_id)
    )
}


table_data_prep <- function(df_base, rv_carry_thru, df_grey_player, pin_date, post_matchup_days = 2) {
  if (!"lineup_slot" %in% names(df_base)) {
    df_base$lineup_slot <- rep(NA_character_, nrow(df_base))
  }

  df_wide <- df_base |>
    arrange(game_date) |>
    mutate(
      benched = !is_starting_lineup(lineup_slot) &
        !is.na(game_date) &
        game_date < cur_date
    ) |>
    select(
      competitor,
      competitor_id,
      player_team,
      player_id,
      player_name,
      inj_status,
      fmt_date,
      scheduled_to_play,
      benched
    ) |>
    distinct() |>
    mutate(
      scheduled_to_play = as.character(replace_na(scheduled_to_play, 0)),
      suffix = case_when(
        inj_status == "Out" ~ "*",
        benched ~ "b",
        TRUE ~ ""
      ),
      scheduled_to_play = str_c(scheduled_to_play, suffix)
    ) |>
    select(-inj_status, -benched, -suffix) |>
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
        values <- c_across(all_of(remaining_cols))
        sum(as.numeric(str_remove_all(values, "[*b]")) * !str_detect(values, "b"), na.rm = TRUE)
      },
      .before = if (all(is.na(df_base$matchup_end_plus))) last_col() else last_col(2)
    ) |>
    ungroup() |>
    left_join(df_grey_player, by = join_by(player_id, competitor_id))
}

table_sum_data_prep <- function(df_tbl, df_base, pin_date, starter_count) {
  df_sum <- df_tbl |>
    summarise(
      across(
        contains("/"),
        \(x) {
          games <- as.numeric(str_remove_all(x, "[*b]"))
          sum(games * !str_detect(x, "[*b]"), na.rm = TRUE)
        }
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

  # The active spots are a ceiling on what a past day could have scored, and
  # lineup slots are missing for older snapshots, so cap once the day is done.
  # Looking forward the count can run over, and is flagged rather than capped.
  past_cols <- names(col_dates)[col_dates < cur_date]
  df_sum <- df_sum |>
    mutate(across(all_of(past_cols), \(x) pmin(x, starter_count)))

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
        daily <- as.numeric(str_remove(c_across(all_of(remaining_cols)), "\\*"))
        sum(pmin(daily, starter_count), na.rm = TRUE)
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
