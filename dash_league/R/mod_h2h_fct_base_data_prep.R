ensure_excluded <- function(df) {
  if (!"excluded" %in% names(df)) {
    df$excluded <- FALSE
  }
  df$excluded <- coalesce(df$excluded, FALSE)
  df
}


# Who owned each added player on the day the move was made. A trade during the
# matchup is attributed to the roster the player was on at the time.
alter_team_add_owner <- function(l_id, add) {
  if (is.null(add) || nrow(add) == 0) {
    return(tibble(player_id = integer(), competitor_id = integer()))
  }

  roster <- pluck(dfs_fty_roster, l_id)
  if (is.null(roster)) {
    return(tibble(player_id = integer(), competitor_id = integer()))
  }

  roster |>
    inner_join(add, by = join_by(player_id)) |>
    filter(assigned_date <= action_date) |>
    slice_max(assigned_date, by = player_id) |>
    distinct(player_id, competitor_id)
}


# Any player who has future games, whether they are on a roster or a free agent.
future_add_source <- function(l_id, matchup, window) {
  buckets <- pluck(dfs_h2h_future, l_id, matchup)

  rostered <- if (is.null(buckets)) {
    NULL
  } else {
    buckets[names(buckets) != "free_agent"] |>
      map(\(cp) pluck(cp, window)) |>
      compact() |>
      list_rbind()
  }

  bind_rows(
    rostered,
    pluck(dfs_h2h_future, l_id, "free_agent", "free_agent", window)
  )
}


base_data_prep <- function(input, rv_carry_thru, opponent, rv_alter_team) {
  if (length(rv_alter_team) > 0) {
    df_alter <- tibble(
      action = map_chr(rv_alter_team, "action"),
      player_id = map_int(rv_alter_team, "player_id"),
      action_date = as.Date(map_chr(rv_alter_team, "action_date"))
    )

    valid_combo <- \(df) if (nrow(df) > 0) df else NULL
    add <- valid_combo(filter(df_alter, action == "add", action_date >= cur_date))
    ex <- valid_combo(filter(df_alter, action == "ex", action_date >= cur_date))
  } else {
    add <- ex <- NULL
  }

  l_id <- as.character(rv_carry_thru$league_id)

  add_owner <- alter_team_add_owner(l_id, add)

  map(na.omit(as.character(c(opponent()$id, rv_carry_thru$competitor_id))), \(x) {
    bind_rows(
      compact(
        lst(
          "past" = if (input$future_only) {
            NULL
          } else {
            pluck(dfs_h2h_past, l_id, input$matchup, x)
          },

          "future" = if (
            x != rv_carry_thru$competitor_id |
              as.integer(input$matchup) < rv_carry_thru$cur_matchup_period
          ) {
            df <- pluck(dfs_h2h_future, l_id, input$matchup, x, input$window)

            if (
              !is.null(df) &&
                nrow(df) > 0 &&
                alter_applies(input, rv_carry_thru) &&
                nrow(add_owner) > 0
            ) {
              owner_add <- add_owner |>
                filter(as.character(competitor_id) == x) |>
                inner_join(add, by = join_by(player_id))

              if (nrow(owner_add) > 0) {
                add_rows <- df |>
                  inner_join(
                    owner_add |> summarise(action_date = min(action_date), .by = player_id),
                    by = join_by(player_id, game_date >= action_date)
                  ) |>
                  mutate(excluded = TRUE, scheduled_to_play = 0) |>
                  select(-action_date)

                df <- df |>
                  anti_join(owner_add, by = join_by(player_id, game_date >= action_date)) |>
                  bind_rows(add_rows)
              }
            }

            df
          } else {
            pluck(dfs_h2h_future, l_id, input$matchup, x, input$window) |>
              (\(df) {
                if (is.null(df)) {
                  return(NULL)
                }

                ex_rows <- NULL
                if (!is.null(ex)) {
                  ex_rows <- df |>
                    inner_join(
                      ex |> summarise(action_date = min(action_date), .by = player_id),
                      by = join_by(player_id, game_date >= action_date)
                    ) |>
                    mutate(excluded = TRUE, scheduled_to_play = 0) |>
                    select(-action_date)
                  # fmt: skip
                  df <- anti_join(df, ex, by = join_by(player_id, game_date >= action_date))
                }

                add_applied <- FALSE
                if (!is.null(add) && nrow(df) > 0) {
                  add_applied <- TRUE
                  current_start <- min(df$matchup_start, na.rm = TRUE)
                  current_end <- max(df$matchup_end, na.rm = TRUE)

                  df <- df |>
                    bind_rows(
                      future_add_source(l_id, input$matchup, input$window) |>
                        inner_join(add, by = join_by(player_id, game_date >= action_date)) |>
                        filter(game_date >= current_start, game_date <= current_end + 2) |>
                        mutate(
                          matchup_start = current_start,
                          matchup_end = current_end,
                          matchup_end_plus = if_else(
                            game_date > current_end,
                            current_end + 2,
                            NA_Date_
                          )
                        )
                    )
                }

                df <- df |> mutate(excluded = FALSE)

                if (!is.null(ex_rows)) {
                  if (add_applied) {
                    ex_rows <- anti_join(ex_rows, distinct(add, player_id), by = join_by(player_id))
                  }
                  df <- bind_rows(df, ex_rows)
                }

                df
              })()
          }
        )
      ),
      .id = "tense"
    ) |>
      ensure_excluded() |>
      mutate(
        competitor_id = as.integer(x),
        competitor = pluck(ls_fty_lookup, "cp_id_to_name", l_id, x)
      )
  }) |>
    list_rbind() |>
    mutate(
      competitor = if (is.na(opponent()$id)) {
        pluck(ls_fty_lookup, "cp_id_to_name", l_id, as.character(rv_carry_thru$competitor_id))
      } else {
        ordered(
          competitor,
          c(
            pluck(ls_fty_lookup, "cp_id_to_name", l_id, as.character(rv_carry_thru$competitor_id)),
            pluck(ls_fty_lookup, "cp_id_to_name", l_id, as.character(opponent()$id))
          )
        )
      }
    )
}
