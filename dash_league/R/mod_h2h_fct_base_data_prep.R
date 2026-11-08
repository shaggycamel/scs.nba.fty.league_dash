ensure_excluded <- function(df) {
  if (!"excluded" %in% names(df)) {
    df$excluded <- FALSE
  }
  df$excluded <- coalesce(df$excluded, FALSE)
  df
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
            pluck(dfs_h2h_future, l_id, input$matchup, x, input$window)
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
                      dfs_h2h_future |>
                        pluck(l_id, "free_agent", "free_agent", input$window) |>
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
