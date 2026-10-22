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
                # fmt: skip
                if (!is.null(ex)) df <- anti_join(df, ex, by = join_by(player_id, game_date >= action_date))
                if (!is.null(add) && nrow(df) > 0) {
                  current_start <- min(df$matchup_start, na.rm = TRUE)
                  current_end <- max(df$matchup_end, na.rm = TRUE)

                  df <- df |>
                    bind_rows(
                      dfs_h2h_future |>
                        pluck(l_id, "free_agent", "free_agent", input$window) |>
                        inner_join(add, by = join_by(player_id, game_date >= action_date)) |>
                        filter(game_date <= current_end + 2) |>
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
                df
              })()
          }
        )
      ),
      .id = "tense"
    ) |>
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
