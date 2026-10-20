#' schedule_table UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
mod_schedule_table_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_sidebar(
      sidebar = sidebar(
        selectInput(ns("matchup_selection"), "Matchup", choices = character(0), selectize = FALSE),
        dateInput(ns("pin_date"), "Pinned Date"),
        radioButtons(ns("pin_dir"), label = "Pin Direction", choices = c("-", "+"), selected = "+", inline = TRUE),
        actionButton(ns("copy_teams"), "Copy teams to Comparison")
      ),
      card(full_screen = TRUE, shinycssloaders::withSpinner(reactableOutput(ns("schedule_table")), type = 1, color = "#133DEF")),
      fillable = TRUE
    ),
  )
}

#' schedule_table Server Functions
#'
#' @noRd
#'
mod_schedule_table_server <- function(id, rv_carry_thru, rv_copy_teams) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Initialise & Filter Reactivity --------------------------------------------------------

    # On load...
    observe({
      req(rv_carry_thru$fty_parameters_met)

      matchups <- pluck(dfs_fty_nba_mup_weeks, as.character(rv_carry_thru$league_id))
      req(matchups)
      chs <- names(matchups)
      periods <- matchup_period_from_label(chs)

      # same clamp as mod_h2h
      fallback <- if (rv_carry_thru$cur_matchup_period == 99) 99L else as.integer(rv_carry_thru$cur_matchup_period)
      selected_period <- resolve_matchup_selection(
        matchup_period_from_label(isolate(input$matchup_selection)),
        periods,
        fallback
      )

      updateSelectInput(
        session = session,
        inputId = "matchup_selection",
        choices = chs,
        selected = chs[match(selected_period, periods)]
      )

      schedule <- pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id))
      req(schedule)
      mup_min_max_dts <- schedule |>
        distinct(matchup_period, matchup_start, matchup_end) |>
        filter(matchup_period == selected_period)

      req(nrow(mup_min_max_dts) > 0)

      updateDateInput(
        session,
        "pin_date",
        value = cur_date,
        min = mup_min_max_dts$matchup_start,
        max = mup_min_max_dts$matchup_end
      )

      updateRadioButtons(session, "pin_dir", choices = c("-", "+"), selected = "+", inline = TRUE)
    }) |>
      bindEvent(rv_carry_thru$fty_parameters_met, rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    observe({
      req(df_tbl())
      updateReactable("schedule_table", data = df_tbl(), selected = NA)
    }) |>
      bindEvent(rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    # On matchup_selection change...
    observe({
      req(rv_carry_thru$fty_parameters_met)

      schedule <- pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id))
      req(schedule)
      mup_min_max_dts <- schedule |>
        filter(matchup_period == matchup_period_from_label(input$matchup_selection)) |>
        distinct(matchup_period, matchup_start, matchup_end)

      req(nrow(mup_min_max_dts) > 0)

      updateDateInput(
        session,
        "pin_date",
        value = if (between(as.Date(cur_date), mup_min_max_dts$matchup_start, mup_min_max_dts$matchup_end)) {
          cur_date
        } else if (as.Date(cur_date) > mup_min_max_dts$matchup_end) {
          mup_min_max_dts$matchup_end
        } else {
          mup_min_max_dts$matchup_start
        },
        min = mup_min_max_dts$matchup_start,
        max = mup_min_max_dts$matchup_end
      )
    }) |>
      bindEvent(input$matchup_selection, ignoreInit = TRUE, ignoreNULL = FALSE)

    # On copy_teams
    observe({
      req(rv_carry_thru$fty_parameters_met)

      week <- dfs_fty_nba_mup_weeks |>
        pluck(as.character(rv_carry_thru$league_id), input$matchup_selection)
      req(week)
      selected_values <- week |>
        select(Team) |>
        # mutate(Team = as.character(Team)) |>
        slice(getReactableState("schedule_table", "selected"))

      if (length(selected_values$Team) == 0) {
        show_toast(
          title = NULL,
          text = "No teams selected. Comparison not updated...",
          position = "bottom-start",
          type = "warning",
          timer = 2000
        )
      } else {
        rv_copy_teams(selected_values$Team)
        show_toast(
          title = NULL,
          text = "Teams added to comparison...",
          position = "bottom-start",
          type = "info",
          timer = 2000
        )
        updateReactable("schedule_table", selected = integer(0))
      }
    }) |>
      bindEvent(input$copy_teams, ignoreInit = TRUE)

    # Data Prep --------------------------------------------------------------

    # Pinned date calculations
    mup_dts <- reactive({
      req(rv_carry_thru$fty_parameters_met, input$matchup_selection != "")

      schedule <- pluck(dfs_fty_schedule, as.character(rv_carry_thru$league_id))
      req(schedule)
      schedule |>
        filter(matchup_period == matchup_period_from_label(input$matchup_selection)) |>
        distinct(matchup_period, matchup_start, matchup_end)
    }) |>
      bindEvent(input$matchup_selection, rv_carry_thru$league_id, rv_carry_thru$fty_parameters_met)

    # The matchup week, with a column for every day rather than only the days
    # that have games - see fill_missing_days()
    df_week <- reactive({
      req(nrow(mup_dts()) > 0)

      # the old league's label can linger until the browser catches up
      week <- pluck(dfs_fty_nba_mup_weeks, as.character(rv_carry_thru$league_id), input$matchup_selection)
      req(!is.null(week))

      fill_missing_days(week, mup_dts()$matchup_start, mup_dts()$matchup_end)
    })

    # Real date behind each column label - see col_dates_from_labels()
    col_dates <- reactive(col_dates_from_labels(names(df_week()), mup_dts()$matchup_start))

    # Data for reactive table
    df_tbl <- reactive({
      req(nrow(mup_dts()) > 0, input$pin_date)

      pin_cols <- if (input$matchup_selection == "Post Fantasy") {
        character(0)
      } else {
        pin_columns(
          col_dates(),
          input$pin_date,
          mup_dts()$matchup_start,
          mup_dts()$matchup_end,
          input$pin_dir
        )
      }

      df_week() |>
        rowwise() |>
        mutate(Pin = sum(c_across(all_of(pin_cols)))) |>
        ungroup()
    }) |>
      bindEvent(input$matchup_selection, input$pin_dir, input$pin_date)

    # Schedule Table ---------------------------------------------------------

    # Table state
    rv_tbl_sort_order <- reactiveVal()
    cur_tbl_sort_order <- reactive(getReactableState("comparison_table", "sorted", session = session))
    observe(rv_tbl_sort_order(cur_tbl_sort_order())) |> bindEvent(cur_tbl_sort_order())

    output$schedule_table <- renderReactable({
      req(df_tbl())

      # Shiny ignores elementId and keys the widget off the namespaced output id
      tbl_id <- ns("schedule_table")

      # Column formatting
      col_fmt <- map(set_names(str_subset(colnames(df_tbl()), "\\/")), \(x) {
        nm <- str_split_1(x, " ")
        colDef(
          header = tags$span(nm[1], tags$br(), nm[2]),
          filterInput = \(values, name) {
            tags$select(
              onchange = sprintf("Reactable.setFilter('%s', '%s', event.target.value || undefined)", tbl_id, name),
              tags$option(value = "", ""),
              lapply(c(0, 1), tags$option),
              "aria-label" = sprintf("Filter %s", name),
              style = "width: 100%; height: 28px;"
            )
          },
          style = if (col_dates()[[x]] > mup_dts()$matchup_end) {
            list(backgroundColor = "#eee5ff94")
          } else if (col_dates()[[x]] == input$pin_date) {
            list(backgroundColor = "#f1e78e94")
          }
        )
      })
      col_fmt[["Team"]] <- colDef(
        sticky = "left",
        style = list(backgroundColor = "#c1eccaff", fontWeight = "bold"),
        filterInput = \(values, name) {
          dataListId <- sprintf("%s-%s-list", tbl_id, name)
          tagList(
            tags$input(
              type = "text",
              list = dataListId,
              oninput = sprintf(
                "Reactable.setFilter('%s', '%s', event.target.value || undefined)",
                tbl_id,
                name
              ),
              "aria-label" = sprintf("Filter %s", name),
              style = "width: 100%; height: 28px;"
            ),
            tags$datalist(
              id = dataListId,
              lapply(unique(values), function(value) tags$option(value = value))
            )
          )
        }
      )
      col_fmt[["Pin"]] <- colDef(
        sticky = "left",
        style = list(backgroundColor = "#c1eccaff", fontWeight = "bold", borderRight = "2px solid #0f0f0fff"),
        headerStyle = list(
          background = "#cce5ff",
          fontWeight = "bold",
          textAlign = "center",
          borderRight = "2px solid #0f0f0fff"
        ),
        filterMethod = JS(
          "function(rows, columnId, filterValue) {
            return rows.filter(function(row) {
              return row.values[columnId] >= filterValue
            })
          }"
        )
      )

      reactable(
        df_tbl(),
        defaultSorted = rv_tbl_sort_order(),
        defaultColDef = colDef(headerStyle = list(background = "#cce5ff", fontWeight = "bold", textAlign = "center")),
        selection = "multiple",
        filterable = TRUE,
        striped = TRUE,
        highlight = TRUE,
        bordered = TRUE,
        pagination = FALSE,
        height = "85vh",
        wrap = TRUE,
        columns = col_fmt
      )
    })
  })
}

## To be copied in the UI
# mod_schedule_table_ui("schedule_table_1")

## To be copied in the server
# mod_schedule_table_server("schedule_table_1")

# library(shiny)
# library(bslib)
# library(reactable)
# library(stringr)
# library(purrr)
# library(dplyr)
# library(tidyr)
# library(shinyWidgets)
# library(lubridate)
# load("data/dfs_fty_nba_mup_weeks.rda")
# load("data/dfs_fty_schedule.rda")
# load("data/cur_date.rda")

# ui <- page_fluid(
#   mod_schedule_table_ui("schedule_table_1")
# )

# server <- function(input, output, session) {
# rv_carry_thru <- reactiveValues(
#   fty_parameters_met = TRUE,
#   platform = "ESPN",
#   league_id = 1382487116,
#   competitor_id = 6,
#   competitor_name = "britney_spears",
#   cur_matchup_period = 99
# )

#   mod_schedule_table_server("schedule_table_1", rv_carry_thru)
# }

# shinyApp(ui, server)
