#' h2h UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
mod_h2h_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_sidebar(
      sidebar = sidebar(
        selectizeInput(ns("matchup"), NULL, choices = 0),
        radioButtons(ns("window"), NULL, c(7, 15, 30), inline = TRUE),
        selectInput(ns("hl_player"), NULL, choices = character(0), multiple = TRUE),
        layout_columns(
          dateInput(ns("pin_date"), NULL, weekstart = 1),
          checkboxInput(ns("future_only"), NULL),
          col_widths = c(8, 4)
        ),
        actionButton(ns("alter_team"), "Alter Team"),
        shinycssloaders::withSpinner(reactableOutput(ns("alter_team_table")), type = 1, color = "#133DEF"),
        actionButton(ns("snapshot_config"), "📸 Take Snapshot"),
        shinycssloaders::withSpinner(reactableOutput(ns("snapshot_table")), type = 1, color = "#133DEF")
      ),
      card(
        fill = FALSE,
        uiOutput(ns("plot_card")),
        card(
          full_screen = TRUE,
          fill = FALSE,
          bslib::card_body(
            max_height = 650,
            max_height_full_screen = NULL,
            shinycssloaders::withSpinner(reactableOutput(ns("game_table")), type = 1, color = "#133DEF")
          )
        )
      ),
      fillable = TRUE,
      tags$style(
        type = "text/css",
        ".selectize-dropdown-content{width: 200px;background-color: #FFFFFF; align: right;}"
      )
    )
  )
}


#' h2h Server Functions
#'
#' @noRd
#'
mod_h2h_server <- function(
  id,
  rv_carry_thru,
  rv_alter_team,
  rv_alter_team_modal_vals,
  rv_alter_team_trigger,
  rv_snapshot_log,
  rv_snapshot_trigger
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Update UI --------------------------------------------------------------

    observe({
      req(rv_carry_thru$fty_parameters_met)

      matchup_periods <- pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id)) |>
        distinct(matchup, matchup_period) |>
        arrange(matchup_period)

      # keep the selected week across a switch, unless the new league is shorter
      selected <- resolve_matchup_selection(
        isolate(input$matchup),
        matchup_periods$matchup_period,
        rv_carry_thru$cur_matchup_period
      )

      updateSelectizeInput(
        session,
        "matchup",
        choices = deframe(matchup_periods),
        selected = selected
      )

      updateSelectInput(
        session,
        "hl_player",
        choices = pluck(dfs_fty_roster, as.character(rv_carry_thru$league_id)) |>
          filter(competitor_id == rv_carry_thru$competitor_id) |>
          slice_max(assigned_date) |>
          arrange(player_name) |>
          select(player_name, player_id) |>
          na.omit() |>
          deframe()
      )
    }) |>
      bindEvent(rv_carry_thru$fty_parameters_met, rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    # Date picker pin_date
    observe({
      req(nrow(df_base()) > 0)

      matchup_start <- max(na.omit(df_base()$matchup_start))
      matchup_end <- max(na.omit(df_base()$matchup_end))

      updateDateInput(
        session,
        "pin_date",
        value = if (between(cur_date, matchup_start, matchup_end)) {
          cur_date
        } else if (cur_date > matchup_end) {
          matchup_end
        } else {
          matchup_start
        },
        min = matchup_start,
        max = matchup_end
      )
    }) |>
      bindEvent(input$matchup, rv_carry_thru$league_id, rv_carry_thru$competitor_id, ignoreInit = TRUE)

    observe({
      req(df_base())

      players_already_hl <- setdiff(
        input$hl_player,
        rv_alter_team() |>
          keep(\(x) x$action == "ex") |>
          map_int("player_id")
      )

      updateSelectInput(
        session,
        "hl_player",
        choices = df_base() |>
          filter(competitor == rv_carry_thru$competitor_name) |>
          arrange(player_name) |>
          select(player_name, player_id) |>
          na.omit() |>
          deframe(),
        selected = players_already_hl
      )
    }) |>
      bindEvent(rv_alter_team(), rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    observe({
      req(opponent())

      # Update modal data
      rv_alter_team_modal_vals$roster <- df_base() |>
        filter(competitor_id == as.integer(rv_carry_thru$competitor_id)) |>
        distinct(player_name, player_id) |>
        arrange(player_name) |>
        deframe()

      free_agents <- dfs_h2h_future |>
        pluck(
          as.character(rv_carry_thru$league_id),
          "free_agent",
          "free_agent",
          "7",
          .default = tibble(player_name = character(), player_id = integer())
        )

      rv_alter_team_modal_vals$free_agents <- free_agents |>
        distinct(player_name, player_id) |>
        anti_join(
          df_base() |>
            filter(competitor_id == as.integer(rv_carry_thru$competitor_id)) |>
            distinct(player_name, player_id),
          by = join_by(player_id)
        ) |>
        na.omit() |>
        deframe()

      rv_alter_team_modal_vals$ui_date <- input$pin_date
      rv_alter_team_modal_vals$mup_end_date <- unique(df_base()$matchup_end)

      rv_alter_team_trigger(isolate(rv_alter_team_trigger()) + 1L)
    }) |>
      bindEvent(input$alter_team)

    # Alter Team Table -------------------------------------------------------

    output$alter_team_table <- renderReactable({
      req(length(rv_alter_team()) > 0)
      selected_players <- names(rv_alter_team())

      df <- tibble(
        key = selected_players,
        action = str_split_i(selected_players, "-", 1),
        player_name = str_split_i(selected_players, "-", 2),
        delete = na_lgl
      )

      reactable(
        df,
        pagination = FALSE,
        sortable = FALSE,
        compact = TRUE,
        wrap = FALSE,
        columns = list(
          key = colDef(show = FALSE),
          action = colDef(name = "Action", maxWidth = 65),
          player_name = colDef(name = "Player", maxWidth = 120),
          delete = colDef(
            name = "",
            maxWidth = 30,
            sortable = FALSE,
            cell = function(value, index) {
              tags$button(
                icon("xmark"),
                class = "btn btn-danger btn-sm",
                onclick = sprintf(
                  "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                  ns("delete_alter_team_key"),
                  df$key[index]
                )
              )
            }
          )
        )
      )
    })

    observe({
      current <- rv_alter_team()
      current[[input$delete_alter_team_key]] <- NULL
      rv_alter_team(current)
    }) |>
      bindEvent(input$delete_alter_team_key)

    # Snapshot config --------------------------------------------------------

    rv_snapshot_pending <- reactiveVal(NULL)
    observe({
      rv_snapshot_trigger(rv_snapshot_trigger() + 1)
      ls_snapshot <- reactiveValuesToList(input)
      ls_snapshot <- list(
        "matchup" = ls_snapshot$matchup,
        "hl_player" = ls_snapshot$hl_player,
        "pin_date" = ls_snapshot$pin_date,
        "window" = ls_snapshot$window,
        "future_only" = ls_snapshot$future_only,
        "alter_team" = rv_alter_team()
      )

      rv_snapshot_pending(ls_snapshot)

      showModal(
        modalDialog(
          title = NULL,
          {
            ti <- textInput(ns("snapshot_name"), NULL, value = paste0("snapshot_", rv_snapshot_trigger()))
            ti$children[[2]]$attribs$maxlength <- 20
            ti
          },
          footer = tagList(
            div(
              style = "display: flex; align-items: center; justify-content: space-between; width: 100%;",
              span(textOutput(ns("snapshot_error_msg")), style = "color:red;"),
              div(
                style = "display: flex; gap: 8px;",
                modalButton("Cancel"),
                actionButton(
                  ns("confirm_snapshot_name"),
                  "Kobeee!",
                  style = "color:#FFF; background-color:#337AB7; border-color:#2E6DA4"
                )
              )
            )
          )
        )
      )
    }) |>
      bindEvent(input$snapshot_config)

    observe({
      name_raw <- str_trim(input$snapshot_name)
      is_dupe <- name_raw %in% names(rv_snapshot_log())
      toggleState(id = "confirm_snapshot_name", condition = nzchar(name_raw) && !is_dupe)
      if (is_dupe) {
        output$snapshot_error_msg <- renderText("Snapshot id already exists...")
      }
      if (!nzchar(name_raw)) {
        output$snapshot_error_msg <- renderText("Snapshot id can't be empty...")
      }
    }) |>
      bindEvent(input$snapshot_name)

    observe({
      current <- rv_snapshot_log()
      current[[str_trim(input$snapshot_name)]] <- rv_snapshot_pending()
      rv_snapshot_log(current)
      rv_snapshot_pending(NULL)
      output$snapshot_error_msg <- NULL
      removeModal()
    }) |>
      bindEvent(input$confirm_snapshot_name)

    output$snapshot_table <- renderReactable({
      req(length(rv_snapshot_log()) > 0)
      snapshots <- names(rv_snapshot_log())

      df <- tibble(
        snap = snapshots,
        delete = na_lgl
      )

      reactable(
        df,
        pagination = FALSE,
        sortable = FALSE,
        compact = TRUE,
        wrap = FALSE,
        theme = reactableTheme(headerStyle = list(display = "none")),
        columns = list(
          snap = colDef(
            name = "",
            cell = function(value, index) {
              tags$span(
                value,
                onclick = sprintf(
                  "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                  ns("select_snapshot"),
                  df$snap[index]
                ),
                style = "cursor: pointer;"
              )
            }
          ),
          delete = colDef(
            name = "",
            maxWidth = 30,
            sortable = FALSE,
            cell = function(value, index) {
              tags$button(
                icon("xmark"),
                class = "btn btn-danger btn-sm",
                onclick = sprintf(
                  "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                  ns("delete_snapshot"),
                  df$snap[index]
                )
              )
            }
          )
        )
      )
    })

    observe({
      current <- rv_snapshot_log()
      current[[input$delete_snapshot]] <- NULL
      rv_snapshot_log(current)
    }) |>
      bindEvent(input$delete_snapshot)

    observe({
      vals <- rv_snapshot_log()[[input$select_snapshot]]
      updateSelectInput(session, "matchup", selected = vals$matchup)
      updateSelectInput(
        session,
        "hl_player",
        choices = df_base() |>
          filter(competitor == rv_carry_thru$competitor_name) |>
          arrange(player_name) |>
          select(player_name, player_id) |>
          na.omit() |>
          deframe(),
        selected = vals$hl_player
      )
      updateDateInput(session, "pin_date", value = vals$pin_date)
      updateSliderInput(session, "window", value = vals$window)
      updateCheckboxInput(session, "future_only", value = vals$future_only)
      rv_alter_team(vals$alter_team)
    }) |>
      bindEvent(input$select_snapshot)

    # Data prep --------------------------------------------------------------

    opponent <- reactive({
      req(input$matchup > 0)
      get_opponent(rv_carry_thru, as.numeric(input$matchup))
    }) |>
      bindEvent(input$matchup, rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    league_regular_periods <- reactive({
      pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id)) |>
        filter(matchup_period != 99) |>
        pull(matchup_period)
    }) |>
      bindEvent(rv_carry_thru$league_id, rv_carry_thru$fty_parameters_met)

    df_base <- reactive({
      req(opponent())
      # previous league's week (or Post Fantasy) has no data here
      req(as.integer(input$matchup) %in% league_regular_periods())
      base_data_prep(input, rv_carry_thru, opponent, rv_alter_team())
    }) |>
      bindEvent(opponent(), rv_alter_team(), input$future_only, input$window, ignoreInit = FALSE)

    df_plt <- reactive({
      if (identical(as.character(input$matchup), "99")) {
        df_postseason <- postseason_base_data_prep(
          pluck(dfs_h2h_past, as.character(rv_carry_thru$league_id)),
          rv_carry_thru$competitor_id,
          rv_carry_thru$competitor_name
        )
        req(nrow(df_postseason) > 0)
        return(plot_data_prep(df_postseason, rv_carry_thru))
      }

      req(nrow(df_base()) > 0)
      plot_data_prep(df_base(), rv_carry_thru)
    })

    df_grey_player <- reactive({
      req(nrow(df_base()) > 0)
      grey_player_data_prep(input, df_base(), rv_carry_thru, opponent)
    })

    # the last matchup has no following week to look ahead to
    post_matchup_days <- reactive({
      schedule <- pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id))
      last_regular <- max(schedule$matchup_period[schedule$matchup_period != 99], na.rm = TRUE)
      if (as.integer(input$matchup) == last_regular) 0L else 2L
    }) |>
      bindEvent(input$matchup, rv_carry_thru$league_id)

    df_tbl <- reactive({
      req(nrow(df_base()) > 0, df_grey_player(), input$pin_date)
      table_data_prep(
        df_base(),
        rv_carry_thru,
        df_grey_player(),
        as.Date(input$pin_date),
        post_matchup_days()
      )
    })

    df_tbl_sum <- reactive({
      req(df_tbl())
      table_sum_data_prep(df_tbl(), df_base(), as.Date(input$pin_date))
    })

    # Plot -------------------------------------------------------------------

    is_points_league <- reactive({
      req(rv_carry_thru$fty_parameters_met)
      df_fty_cat_weights |>
        filter(
          league_id == as.integer(rv_carry_thru$league_id),
          !is.na(points)
        ) |>
        nrow() > 0
    })

    output$stat_plot <- renderD3({
      req(df_plt())

      r2d3(
        data = df_plt(),
        script = app_sys("d3/h2h_stat_plot/h2h_stat_plot.js"),
        options = list(
          expanded = isTRUE(input$h2h_plot_expanded),
          toggle_input = ns("h2h_plot_expanded")
        )
      )
    })

    output$plot_card <- renderUI({
      req(rv_carry_thru$fty_parameters_met)
      # Read the toggle state in isolation: the D3 click animates this card's
      # height itself, and re-rendering the card here would replace it mid-flight.
      collapsed <- is_points_league() && !isTRUE(isolate(input$h2h_plot_expanded))

      card(
        full_screen = TRUE,
        class = "h2h-plot-card",
        height = if (collapsed) 200 else 700,
        shinycssloaders::withSpinner(d3Output(ns("stat_plot"), height = "100%"), type = 1, color = "#133DEF")
      )
    })

    # Game Table -------------------------------------------------------------

    output$game_table <- renderReactable({
      if (input$matchup == "99") {
        roster <- pluck(dfs_fty_roster, as.character(rv_carry_thru$league_id)) |>
          postseason_roster_data_prep(rv_carry_thru$competitor_id)

        req(nrow(roster) > 0)

        return(reactable(
          roster,
          pagination = FALSE,
          bordered = TRUE,
          style = list(border = "1px solid #000000"),
          rowStyle = list(borderBottom = "1px solid #000000"),
          theme = reactableTheme(headerStyle = list(borderBottom = "1px solid #000000")),
          highlight = TRUE,
          sortable = FALSE,
          defaultColDef = colDef(headerStyle = list(background = "#cce5ff")),
          columns = list(
            player_id = colDef(show = FALSE),
            player_team = colDef(name = "NBA Team", minWidth = 70, sticky = "left"),
            player_name = colDef(name = "Player", minWidth = 115)
          )
        ))
      }

      req(df_tbl_sum(), df_tbl(), df_grey_player())
      hl_players <- as.numeric(input$hl_player)

      mup_end <- unique(na.omit(df_base()$matchup_end))
      # Read off the table rather than df_base, which has no rows for the days
      # that fill_missing_days() added.
      col_dates <- col_dates_from_labels(names(df_tbl()), min(df_base()$matchup_start, na.rm = TRUE))
      starter_count <- pluck(
        ls_fty_lookup,
        "lg_id_to_starter_count",
        as.character(rv_carry_thru$league_id),
        .default = 10
      )
      if (is.null(starter_count) || is.na(starter_count)) starter_count <- 10

      col_fmt <- game_tbl_col_fmt(
        df_tbl(), input$pin_date, mup_end, col_dates,
        starter_count = starter_count
      )
      col_fmt_sum <- game_tbl_col_fmt(
        df_tbl_sum(), input$pin_date, mup_end, col_dates,
        type = "sum", starter_count = starter_count
      )

      reactable(
        df_tbl_sum(),
        pagination = FALSE,
        bordered = TRUE,
        style = list(border = "1px solid #000000"),
        rowStyle = list(borderBottom = "1px solid #000000"),
        theme = reactableTheme(headerStyle = list(borderBottom = "1px solid #000000")),
        highlight = TRUE,
        sortable = FALSE,
        defaultColDef = colDef(headerStyle = list(background = "#cce5ff")),
        columns = col_fmt_sum,
        defaultExpanded = TRUE,
        details = \(ix) {
          df_details <- filter(df_tbl(), competitor == df_tbl_sum()$player_team[ix])

          tags$div(
            style = "margin-left: 45px; margin-top: 10px; margin-bottom: 30px;",
            reactable(
              df_details,
              pagination = FALSE,
              bordered = TRUE,
              style = list(border = "1px solid #000000"),
              highlight = TRUE,
              theme = reactableTheme(headerStyle = list(display = "none")),
              defaultSorted = list(player_team = "asc", player_name = "asc"),
              defaultColDef = colDef(headerStyle = list(background = "#cce5ff")), # Not sure if needed
              columns = col_fmt,
              rowStyle = function(index) {
                if (df_details$player_id[index] %in% hl_players) {
                  list(backgroundColor = "#ffef9dff", fontWeight = "bold") # Light yellow highlight
                }
              },
            )
          )
        }
      )
    })
  })
}

## To be copied in the UI
# mod_h2h_ui("h2h_1")

## To be copied in the server
# mod_h2h_server("h2h_1")

# library(shiny)
# library(bslib)
# library(shinyWidgets)
# library(shinyjs)
# library(reactable)
# library(r2d3)
# library(stringr)
# library(purrr)
# library(tibble)
# library(dplyr)
# library(tidyr)
# library(scales)
# library(lubridate)
# library(rlang)
# library(forcats)

# load("data/cur_date.rda")
# load("data/ls_fty_lookup.rda")
# load("data/ls_lo_lg_cats.rda")
# load("data/dfs_fty_schedule.rda")
# load("data/dfs_fty_roster.rda")
# load("data/dfs_h2h_past.rda")
# load("data/dfs_h2h_future.rda")

# source("R/app_config.R")
# source("R/mod_h2h_fct_base_data_prep.R")
# source("R/mod_h2h_fct_plot_data_prep.R")
# source("R/mod_h2h_fct_table_data_prep.R")
# source("R/mod_h2h_fct_table_col_fmt.R")
# source("R/utils_get_opponent.R")
# source("R/mod_modal_alter_team.R")
# source("R/mod_h2h_fct_base_data_prep.R")

# ui <- page_fluid(
#   shinyjs::useShinyjs(),
#   mod_h2h_ui("h2h_1")
# )

# server <- function(input, output, session) {
#   rv_carry_thru <- reactiveValues(
#     fty_parameters_met = TRUE,
#     platform = "ESPN",
#     league_id = 95537,
#     competitor_id = 26,
#     competitor_name = "Daisies",
#     cur_matchup_period = 99
#   )
#   rv_alter_team <- reactiveVal(list())
#   rv_alter_team_modal_vals <- reactiveValues()
#   rv_alter_team_trigger <- reactiveVal(0L)
#   rv_snapshot_log <- reactiveVal(list())
#   rv_snapshot_trigger <- reactiveVal(0L)

#   mod_h2h_server(
#     "h2h_1",
#     rv_carry_thru,
#     rv_alter_team,
#     rv_alter_team_modal_vals,
#     rv_alter_team_trigger,
#     rv_snapshot_log,
#     rv_snapshot_trigger
#   )
#   mod_modal_alter_team_server("modal_alter_team_1", rv_alter_team, rv_alter_team_modal_vals, rv_alter_team_trigger)
# }

# shinyApp(ui, server)
