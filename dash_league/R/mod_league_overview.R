#' league_overview UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
mod_league_overview_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$head(
      tags$style(HTML(".selectize-dropdown-content{min-width: 100%; box-sizing: border-box;}"))
    ),
    layout_sidebar(
      sidebar = sidebar(
        selectInput(ns("fty_lg_ov_cat"), "Category", choices = character(0)),
        switchInput(ns("fty_lg_ov_rank_toggle"), value = TRUE, onLabel = "Rank", offLabel = "Value", size = "small"),
        switchInput(ns("fty_lg_ov_cum_toggle"), value = TRUE, onLabel = "W2W", offLabel = "Cum", size = "small"),
        checkboxInput(ns("fty_lg_ov_just_h2h"), "Just H2H")
      ),
      card(
        height = 1250,
        fill = FALSE,
        navset_card_tab(
          full_screen = TRUE,
          height = 600,
          nav_panel(
            "Standings",
            shinycssloaders::withSpinner(reactableOutput(ns("standings_table")), type = 1, color = "#133DEF")
          ),
          nav_panel(
            "Category Trend",
            shinycssloaders::withSpinner(r2d3::d3Output(ns("fty_lo_plt"), height = "100%"), type = 1, color = "#133DEF")
          )
        ),
        card(
          full_screen = TRUE,
          min_height = 200,
          max_height = 650,
          shinycssloaders::withSpinner(reactableOutput(ns("recent_activity_table")), type = 1, color = "#133DEF")
        )
      )
    )
  )
}


#' league_overview Server Functions
#'
#' @noRd
#'
mod_league_overview_server <- function(id, rv_carry_thru) {
  moduleServer(id, function(input, output, session) {
    # Update categories ------------------------------------------------------

    observe({
      req(rv_carry_thru$fty_parameters_met)
      updateSelectInput(
        session = session,
        inputId = "fty_lg_ov_cat",
        choices = pluck(ls_lo_lg_cats, as.character(rv_carry_thru$league_id))
      )
    }) |>
      bindEvent(rv_carry_thru$fty_parameters_met) # Bind event of when league is swapped too

    # Data prep --------------------------------------------------------------

    df_lo <- reactive(pluck(dfs_league_overview, as.character(rv_carry_thru$league_id)))
    df_lo_pt <- reactive(filter(df_lo(), as.integer(matchup_sigmoid) == matchup_sigmoid))
    opponent <- reactive(get_opponent(rv_carry_thru, rv_carry_thru$cur_matchup_period))

    df_tbl <- reactive({
      req(rv_carry_thru$fty_parameters_met)

      if (input$fty_lg_ov_just_h2h) {
        pluck(dfs_fty_recent_activity, as.character(rv_carry_thru$league_id)) |>
          filter(competitor_id %in% c(rv_carry_thru$competitor_id, opponent()$id))
      } else {
        pluck(dfs_fty_recent_activity, as.character(rv_carry_thru$league_id))
      }
    }) |>
      bindEvent(
        rv_carry_thru$fty_parameters_met,
        input$fty_lg_ov_just_h2h,
        rv_carry_thru$league_id,
        rv_carry_thru$competitor_id
      )

    # Plot -------------------------------------------------------------------

    output$fty_lo_plt <- r2d3::renderD3({
      req(rv_carry_thru$fty_parameters_met, df_lo())

      plot_col <- input$fty_lg_ov_cat
      if (input$fty_lg_ov_rank_toggle) {
        plot_col <- str_c(plot_col, "_rank")
      }

      req(plot_col %in% colnames(df_lo()))
      text_col <- paste0(str_remove(plot_col, "_rank"), "_text")

      # Same branch as before: W2W uses df_lo() directly (already
      # cumulative-style), Cum recomputes cumsum() per competitor off the
      # sparse df_lo_pt() rows only.
      df_plot <- if (input$fty_lg_ov_cum_toggle) {
        df_lo() |>
          mutate(is_point = as.integer(matchup_sigmoid) == matchup_sigmoid)
      } else {
        df_lo_pt() |>
          arrange(matchup) |>
          mutate(across(-matches("_id$|^matchup"), \(x) cumsum(x)), .by = competitor_name) |>
          mutate(is_point = TRUE) # every row is a real matchup period in this branch
      }

      req(plot_col %in% colnames(df_plot), text_col %in% colnames(df_plot) || !input$fty_lg_ov_cum_toggle)

      # Reshape to the generalized value/value_text contract the JS expects,
      # so it never needs to know the actual category column name.
      df_send <- df_plot |>
        transmute(
          competitor_name,
          matchup_sigmoid,
          matchup,
          is_point,
          value = !!sym(plot_col),
          value_text = if (text_col %in% colnames(df_plot)) !!sym(text_col) else NA_character_
        )

      highlight_only <- if (input$fty_lg_ov_just_h2h) {
        c(rv_carry_thru$competitor_name, if (!is.na(opponent()$id)) opponent()$name else NULL)
      } else {
        list() # empty -> JS shows everyone at full opacity
      }

      r2d3::r2d3(
        data = df_send,
        script = app_sys("d3/league_overview/league_overview.js"),
        options = list(
          is_rank = input$fty_lg_ov_rank_toggle,
          title = paste("Competitor Category Ranking:", input$fty_lg_ov_cat),
          competitors = I(unique(df_send$competitor_name)), # TODO: replace with a stable explicit order if available
          highlight_only = I(highlight_only)
        )
      )
    })

    # Standings --------------------------------------------------------------

    df_standings <- reactive({
      req(rv_carry_thru$fty_parameters_met)
      pluck(dfs_fty_standings, as.character(rv_carry_thru$league_id))
    }) |>
      bindEvent(rv_carry_thru$fty_parameters_met, rv_carry_thru$league_id)

    col_fmt_standings <- list(
      rank = colDef(name = "Rank", width = 60),
      competitor_id = colDef(show = FALSE),
      competitor_name = colDef(name = "Competitor"),
      wins = colDef(name = "W", width = 55),
      losses = colDef(name = "L", width = 55),
      ties = colDef(name = "T", width = 55),
      pct = colDef(name = "PCT", format = colFormat(percent = TRUE, digits = 1)),
      points_for = colDef(name = "PF", format = colFormat(digits = 1)),
      points_against = colDef(name = "PA", format = colFormat(digits = 1))
    )

    output$standings_table <- renderReactable({
      req(df_standings())
      df <- df_standings()

      reactable(
        df,
        columns = col_fmt_standings[intersect(names(col_fmt_standings), names(df))],
        pagination = FALSE,
        bordered = TRUE,
        style = list(border = "1px solid #000000", margin = "0 2rem"),
        highlight = TRUE,
        height = "100%",
        defaultColDef = colDef(headerStyle = list(background = "#cce5ff")),
        rowStyle = function(index) {
          if (
            input$fty_lg_ov_just_h2h &&
              df$competitor_id[index] %in% c(rv_carry_thru$competitor_id, opponent()$id)
          ) {
            list(backgroundColor = "#ffef9dff", fontWeight = "bold")
          }
        },
        details = \(ix) {
          df_cat <- pluck(dfs_fty_standings_cats, as.character(rv_carry_thru$league_id)) |>
            filter(competitor_id == df$competitor_id[ix])

          tags$div(
            style = "margin: 10px auto 20px; max-width: 480px; padding: 0 1.5rem;",
            reactable(
              df_cat,
              columns = list(
                competitor_id = colDef(show = FALSE),
                category = colDef(show = FALSE),
                fmt_category = colDef(name = "Category"),
                display_order = colDef(show = FALSE),
                is_ratio = colDef(show = FALSE),
                value = colDef(
                  name = "Season Total",
                  cell = \(value, index) {
                    if (df_cat$is_ratio[index]) {
                      scales::percent(value, accuracy = 0.1)
                    } else {
                      format(round(value, 1), nsmall = 0, big.mark = ",")
                    }
                  }
                ),
                rank = colDef(name = "Rank", width = 80)
              ),
              pagination = FALSE,
              bordered = TRUE,
              style = list(border = "1px solid #000000"),
              highlight = TRUE,
              defaultColDef = colDef(headerStyle = list(background = "#cce5ff"))
            )
          )
        }
      )
    })

    # Table ------------------------------------------------------------------

    # Column formatting
    col_fmt_recent_activity <- list(
      player = colDef(name = "Player"),
      competitor_id = colDef(show = FALSE),
      competitor_name = colDef(
        name = "Competitor",
        filterInput = \(values, name) {
          tags$select(
            onchange = sprintf(
              "Reactable.setFilter('recent-activity-table', '%s', event.target.value || undefined)",
              name
            ),
            tags$option(value = "", ""),
            lapply(unique(values), tags$option),
            "aria-label" = sprintf("Filter %s", name),
            style = "width: 100%; height: 28px;"
          )
        }
      ),
      action = colDef(
        name = "Action",
        filterInput = \(values, name) {
          tags$select(
            onchange = sprintf(
              "Reactable.setFilter('recent-activity-table', '%s', event.target.value || undefined)",
              name
            ),
            tags$option(value = "", ""),
            lapply(unique(values), tags$option),
            "aria-label" = sprintf("Filter %s", name),
            style = "width: 100%; height: 28px;"
          )
        }
      ),
      timestamp = colDef(name = "Time (EST)", cell = \(value) {
        format(value, "%a %d/%m %H:%M", tz = "America/New_York")
      })
    )

    # Table state
    rv_tbl_sort_order <- reactiveVal()
    cur_tbl_sort_order <- reactive(getReactableState("recent_activity_table", "sorted", session = session))
    observe(rv_tbl_sort_order(cur_tbl_sort_order())) |>
      bindEvent(cur_tbl_sort_order())

    output$recent_activity_table <- renderReactable({
      req(df_tbl())

      reactable(
        df_tbl(),
        pagination = FALSE,
        bordered = TRUE,
        style = list(border = "1px solid #000000"),
        highlight = TRUE,
        filterable = TRUE,
        defaultSorted = list(timestamp = "desc"),
        defaultColDef = colDef(headerStyle = list(background = "#cce5ff")),
        columns = col_fmt_recent_activity,
        elementId = "recent-activity-table"
      )
    })
  })
}

## To be copied in the UI
# mod_league_overview_ui("league_overview_1")

## To be copied in the server
# mod_league_overview_server("league_overview_1")

# library(shiny)
# library(bslib)
# library(shinyWidgets)
# library(plotly)
# library(stringr)
# library(purrr)
# library(dplyr)
# library(tidyr)
# library(reactable)

# load("data/dfs_league_overview.rda")
# load("data/dfs_fty_recent_activity.rda")
# load("data/ls_lo_lg_cats.rda")

# source("R/utils_get_opponent.R")

# ui <- page_fluid(
#   mod_league_overview_ui("league_overview_1")
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

#   mod_league_overview_server("league_overview_1", rv_carry_thru)
# }

# shinyApp(ui, server)
