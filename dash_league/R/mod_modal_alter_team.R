#' alter_team_modal UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_modal_alter_team_ui <- function(id) {
  ns <- NS(id)
  tagList(
    fluidPage(ns("blank_page"))
  )
}

#' alter_team_modal Server Functions
#'
#' @noRd
mod_modal_alter_team_server <- function(id, rv_alter_team, rv_alter_team_modal_vals, rv_alter_team_trigger) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Modal Scaffolding ------------------------------------------------------

    observe({
      # req(rv_alter_team_modal_vals)

      showModal(
        modalDialog(
          # tags$head(tags$style(HTML(".selectize-dropdown-content{min-width: 100%; box-sizing: border-box;}"))),

          # Select Action
          layout_columns(
            switchInput(ns("add_or_exclude"), NULL, TRUE, "Add", "Exclude"),
            checkboxInput(ns("free_agent_filter"), "FA", value = TRUE),
            col_widths = c(10, 2),
            gap = "1px"
          ),

          # Select Date
          dateInput(
            ns("action_date"),
            label = NULL,
            value = rv_alter_team_modal_vals$ui_date,
            min = rv_alter_team_modal_vals$ui_date,
            max = rv_alter_team_modal_vals$mup_end_date,
            weekstart = 1
          ),

          # Select Player
          selectizeInput(ns("player"), NULL, choices = character(0), multiple = TRUE),

          # Footer
          footer = tagList(
            span(textOutput(ns("message")), style = "color:red"), # Align left somehow
            actionButton(
              ns("dismiss"),
              label = NULL,
              icon = icon("square-xmark"),
              style = "color:#FFF; background-color:#CD3333; border-color:#2E6DA4"
            ),
            actionButton(
              ns("proceed"),
              "Kobeee!",
              style = "color:#FFF; background-color:#337AB7; border-color:#2E6DA4"
            )
          ),

          # Overall size
          size = "m"
        )
      )
    }) |>
      bindEvent(rv_alter_team_trigger(), ignoreInit = TRUE)

    # Reactive player list ---------------------------------------------------

    add_choices <- reactive({
      if (isFALSE(input$free_agent_filter)) {
        rv_alter_team_modal_vals$all_players
      } else {
        rv_alter_team_modal_vals$free_agents
      }
    })

    observe({
      updateSelectInput(
        inputId = "player",
        choices = if (input$add_or_exclude) {
          add_choices()
        } else {
          rv_alter_team_modal_vals$roster
        },
        selected = character(0)
      )
    }) |>
      bindEvent(input$add_or_exclude, input$proceed, ignoreInit = TRUE)

    observe({
      req(input$add_or_exclude)
      updateSelectInput(inputId = "player", choices = add_choices(), selected = character(0))
    }) |>
      bindEvent(input$free_agent_filter, ignoreInit = TRUE)

    # Proceed button ---------------------------------------------------------

    observe({
      selected_ids <- input$player
      selected_ids <- selected_ids[selected_ids != ""]

      if (length(selected_ids) > 0) {
        current <- rv_alter_team()

        choices <- if (input$add_or_exclude) {
          add_choices()
        } else {
          rv_alter_team_modal_vals$roster
        }

        selected <- choices[choices %in% selected_ids]

        if (length(selected) == 0) {
          output$message <- renderText("Select a player...")
          return()
        }

        keys <- paste0(if (input$add_or_exclude) "add-" else "ex-", names(selected))
        current[keys] <- map2(selected, names(selected), \(id, nm) {
          lst(
            action = if (input$add_or_exclude) "add" else "ex",
            action_date = as.character(input$action_date),
            player_id = as.integer(id),
            player_name = nm
          )
        })

        rv_alter_team(current)
        removeModal()
        output$message <- NULL
      } else {
        output$message <- renderText("Select a player...")
      }
    }) |>
      bindEvent(input$proceed)

    # Dismiss button ---------------------------------------------------------

    observe(removeModal()) |>
      bindEvent(input$dismiss)
  })
}

## To be copied in the UI
# mod_modal_alter_team_ui("modal_alter_team_1")

## To be copied in the server
# mod_modal_alter_team_server("modal_alter_team_1")

# library(shiny)
# library(bslib)
# library(shinyWidgets)
# library(reactable)
# library(plotly)
# library(stringr)
# library(purrr)
# library(tibble)
# library(dplyr)
# library(tidyr)
# library(scales)
# library(lubridate)

# load("data/cur_date.rda")
# load("data/dfs_h2h_future.rda")

# ui <- page_fluid(
#   mod_modal_alter_team_ui("modal_alter_team_1")
# )

# server <- function(input, output, session) {
#   rv_alter_team_trigger <- reactiveVal(0L)
#   rv_alter_team = reactiveValues()
#   rv_alter_team_modal_vals <- reactiveValues(
#     roster = pluck(dfs_h2h_future, "1382487116", "11", "6", "7") |>
#       distinct(player_name, player_id) |>
#       arrange(player_name) |>
#       deframe(),
#     free_agents = pluck(dfs_h2h_future, "1382487116", "free_agent", "free_agent", "7") |>
#       arrange(desc(min)) |>
#       distinct(player_name, player_id) |>
#       deframe(),
#     mup_end_date = as.Date("2026-01-04")
#   )

#   mod_modal_alter_team_server(
#     "modal_alter_team_1",
#     rv_alter_team,
#     rv_alter_team_modal_vals,
#     rv_alter_team_trigger
#   )
# }

# shinyApp(ui, server)
