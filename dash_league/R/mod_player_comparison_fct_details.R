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


# reactable converts detail tags to React without running htmltools render
# hooks, so bslib's Bootstrap 5 nav classes never reach the DOM.
apply_render_hooks <- function(x) {
  if (!inherits(x, "shiny.tag")) {
    return(x)
  }

  for (hook in x$.renderHooks) {
    x <- hook(x)
  }
  x$.renderHooks <- NULL
  x$children <- lapply(x$children, apply_render_hooks)
  x
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


team_depth_chart <- function(player_id, team, depth = ls_team_depth) {
  df <- pluck(depth, as.character(team), .default = tibble())

  if (nrow(df) == 0) {
    return(empty_state("No depth chart available for this team."))
  }

  positions <- intersect(c("G", "F", "C"), unique(df$position_group))

  if (length(positions) == 0) {
    return(empty_state("No depth chart available for this team."))
  }

  columns <- map(positions, \(pos) {
    players <- df |>
      filter(position_group == pos) |>
      arrange(desc(expected_minutes), player_name)

    rows <- map(seq_len(nrow(players)), \(i) {
      selected <- !is.na(player_id) &&
        !is.na(players$player_id[[i]]) &&
        players$player_id[[i]] == player_id
      minutes <- players$expected_minutes[[i]]
      minutes <- if (is.na(minutes)) "-" else formatC(minutes, format = "f", digits = 1)

      tags$div(
        style = str_c(
          "padding: 3px 6px; border: 1px solid #e6e6e6; border-radius: 4px; margin-bottom: 2px;",
          if (selected) " background-color: #f1e78e; font-weight: 700;" else ""
        ),
        tags$div(
          style = "white-space: nowrap; overflow: hidden; text-overflow: ellipsis;",
          players$player_name[[i]]
        ),
        tags$div(style = "font-size: 80%; color: #555;", str_c(minutes, " min"))
      )
    })

    tags$div(
      style = "border: 1px solid #e6e6e6; padding: 4px;",
      tags$div(
        style = str_c(
          "padding: 2px 0; margin-bottom: 4px; border-radius: 4px;",
          " background-color: #cce5ff; font-weight: 700; text-align: center;"
        ),
        pos
      ),
      rows
    )
  })

  opponent <- df$opponent[[1]]
  venue <- if (isFALSE(df$home[[1]])) "@ " else "vs "
  opponent_label <- if (is.na(opponent)) {
    NULL
  } else {
    tags$span(
      style = "font-size: 70%; font-weight: 400; color: #555;",
      str_c(" - ", venue, opponent)
    )
  }

  tagList(
    tags$h2(class = "title", str_c(team, " Depth Chart"), opponent_label),
    tags$div(
      style = "border: 1px solid #e6e6e6; padding: 8px; max-width: 900px;",
      tags$div(
        style = str_c(
          "display: grid; grid-template-columns: repeat(",
          length(positions),
          ", minmax(0, 1fr)); gap: 12px;"
        ),
        columns
      )
    )
  )
}


comparison_details_tabs <- function(
  player_name,
  team,
  player_id,
  window,
  cats,
  cat_weights,
  is_points_league,
  depth = ls_team_depth
) {
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

  depth_chart <- if (is.na(team)) {
    tags$p("Team not found...")
  } else {
    team_depth_chart(player_id, team, depth)
  }

  tags$div(
    style = "margin-left: 45px; margin-top: 10px; margin-bottom: 30px;",
    apply_render_hooks(
      bslib::navset_tab(
        nav_panel("Game Log", game_log),
        nav_panel("Injuries", injuries),
        nav_panel("Depth Chart", depth_chart)
      )
    )
  )
}
