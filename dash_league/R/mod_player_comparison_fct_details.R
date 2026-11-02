player_game_log_data <- function(player_id, cats, cat_weights, is_points_league) {
  df_log <- pluck(
    ls_player_game_log,
    as.character(player_id),
    .default = tibble(
      game_date = as.Date(character()),
      opponent = character(),
      min = numeric()
    )
  )

  if (is_points_league) {
    df_log$fty_pts <- calc_fty_points(df_log, cat_weights)
  }

  df_log |>
    select(game_date, opponent, any_of("fty_pts"), min, any_of(cats))
}


team_injury_data <- function(window, team) {
  pluck(ls_injuries, as.character(window), as.character(team), .default = tibble())
}


details_table <- function(df, empty_text) {
  if (nrow(df) == 0) {
    return(tags$p(empty_text))
  }

  columns <- if ("player_names" %in% names(df)) {
    list(player_names = colDef(minWidth = 1000))
  }

  reactable(
    df,
    pagination = TRUE,
    defaultPageSize = 5,
    fullWidth = FALSE,
    defaultColDef = colDef(
      align = "left",
      minWidth = 120,
      headerStyle = list(background = "#cce5ff")
    ),
    columns = columns
  )
}


comparison_details_tabs <- function(player_name, team, player_id, window, cats, cat_weights, is_points_league) {
  game_log <- if (is.na(player_name)) {
    tags$p("Player not found...")
  } else {
    tagList(
      tags$h2(class = "title", str_c(player_name, " Game Log")),
      details_table(
        player_game_log_data(player_id, cats, cat_weights, is_points_league),
        "No Games"
      )
    )
  }

  injuries <- if (is.na(team)) {
    tags$p("Team not found...")
  } else {
    tagList(
      tags$h2(class = "title", str_c(team, " Last ", window, " Day Injury History")),
      details_table(team_injury_data(window, team), "No Injuries")
    )
  }

  tags$div(
    style = "margin-left: 45px; margin-top: 10px; margin-bottom: 30px;",
    bslib::navset_tab(
      nav_panel("Game Log", game_log),
      nav_panel("Injuries", injuries)
    )
  )
}
