#' player_comparison UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#'
mod_player_comparison_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_sidebar(
      sidebar = sidebar(
        layout_columns(
          switchInput(
            ns("team_player_switch"),
            value = TRUE,
            onLabel = "Team",
            offLabel = "Player",
            size = "small"
          ),
          checkboxInput(ns("free_agent_filter"), "FA", value = TRUE),
          col_widths = c(10, 2),
          gap = "1px"
        ),
        selectInput(ns("team_player_names"), NULL, choices = ls_nba_teams, multiple = TRUE),
        selectizeInput(
          ns("excels_at_filter"),
          "Excels at",
          choices = character(0),
          options = list(maxItems = 5, onInitialize = I('function() { this.setValue(""); }'))
        ),
        radioButtons(ns("window"), "Rolling days", c(7, 15, 30), inline = TRUE),
        sliderInput(ns("minute_filter"), "Minute Filter", min = 0, max = 50, value = 20, round = TRUE),
        switchInput(
          ns("log_inj_toggle"),
          value = TRUE,
          onLabel = "Log",
          offLabel = "Inj",
          size = "small"
        )
      ),
      card(full_screen = TRUE, shinycssloaders::withSpinner(reactableOutput(ns("comparison_table")), type = 1, color = "#133DEF")),
      fillable = TRUE
    )
  )
}

#' player_comparison Server Functions
#'
#' @noRd
#'
mod_player_comparison_server <- function(id, rv_carry_thru, rv_copy_teams) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Widget operation -------------------------------------------------------

    # On load...
    observe({
      req(rv_carry_thru$fty_parameters_met)

      updateSwitchInput(session, "team_player_switch", value = TRUE)
      updateSelectInput(session, "team_player_names", selected = NULL, choices = ls_nba_teams)
      updateRadioButtons(session, "window", selected = 7)
      updateSliderInput(session, "minute_filter", value = 20)
      updateSwitchInput(session, "log_inj_toggle", value = TRUE)
      updateSelectizeInput(
        session,
        "excels_at_filter",
        choices = pluck(
          ls_lo_lg_cats,
          as.character(rv_carry_thru$league_id),
          "Categories"
        )
      )
    }) |>
      bindEvent(rv_carry_thru$fty_parameters_met, rv_carry_thru$league_id, rv_carry_thru$competitor_id)

    # On team player switch...
    observe({
      req(rv_carry_thru$fty_parameters_met)

      chs <- if (input$team_player_switch) {
        # When switch on Team
        ls_nba_teams
      } else {
        # When switch on Player
        ls <- dfs_player_comparison |>
          pluck(
            as.character(rv_carry_thru$league_id),
            as.character(input$window)
          )
        req(ls)
        ls <- ls |>
          filter(!is.na(player_id), !is.na(player_name)) |>
          arrange(desc(min))

        if (input$free_agent_filter) {
          ls <- filter(ls, free_agent)
        }

        ls |>
          select(player_name, player_id) |>
          deframe() |>
          as.list()
      }

      updateSelectInput(session, "team_player_names", choices = chs)
    }) |>
      bindEvent(input$team_player_switch, input$free_agent_filter)

    observe({
      req(rv_copy_teams())
      teams <- unname(ls_nba_teams[rv_copy_teams()])
      updateSwitchInput(session, "team_player_switch", value = TRUE)
      later(\() updateSelectInput(session, "team_player_names", selected = teams), delay = 0.3)
    }) |>
      bindEvent(rv_copy_teams())

    # Data reactivity --------------------------------------------------------

    # Relevant cats
    cats <- reactive({
      ls_lo_lg_cats |>
        pluck(as.character(rv_carry_thru$league_id)) |>
        discard_at(\(x) x == "Overall") |>
        unlist(use.names = FALSE) |>
        discard(\(x) str_like(x, "%_pct"))
    })

    df_comparison <- reactive({
      df <- dfs_player_comparison |>
        pluck(as.character(rv_carry_thru$league_id), as.character(input$window))
      req(df)
      df <- df |>
        filter(min >= input$minute_filter)

      if (input$free_agent_filter) {
        df <- filter(df, free_agent)
      }

      # FILTER TEAM OR PLAYER
      if (!is_null(input$team_player_names)) {
        if (input$team_player_switch) {
          df <- filter(df, team_id %in% input$team_player_names)
        } else {
          df <- filter(df, player_id %in% input$team_player_names)
        }
      }

      # calc excel at here
      df <- df |>
        left_join(
          df |>
            pivot_longer(cols = any_of(cats()), names_to = "category") |>
            mutate(
              rank = case_when(
                category == "tov" ~ percent_rank(-value),
                .default = percent_rank(value)
              ),
              .by = category
            ) |>
            select(player_id, category, rank) |>
            filter(rank >= 0.9) |>
            arrange(player_id, desc(rank)) |>
            summarise(`Excels At` = paste0(category, " (", round(rank, 2), ")", collapse = "\n"), .by = player_id),
          by = join_by(player_id)
        )

      # Excels at filter
      if (!is_null(input$excels_at_filter)) {
        df <- filter(df, str_detect(`Excels At`, paste0(input$excels_at_filter, collapse = "|"))) |>
          mutate(xl_at_count = map_int(`Excels At`, \(x) sum(str_detect(x, input$excels_at_filter))))
      } else {
        df <- mutate(df, xl_at_count = 0)
      }

      df
    })

    # Comparison table -------------------------------------------------------

    # Table state
    rv_tbl_sort_order <- reactiveVal()
    cur_tbl_sort_order <- reactive(getReactableState("comparison_table", "sorted", session = session))
    observe(rv_tbl_sort_order(cur_tbl_sort_order())) |>
      bindEvent(cur_tbl_sort_order())

    output$comparison_table <- renderReactable({
      # df creation
      df <- df_comparison() |>
        select(
          team,
          player_id,
          player = player_name,
          min,
          all_of(cats()),
          `Excels At`,
          `Weak At`,
          inj_status,
          xl_at_count
        )

      # Column formatting
      col_fmt <- map(set_names(c("min", cats())), \(x) {
        colDef(style = function(value) {
          vals <- df[[x]][is.finite(df[[x]])]
          if (value == if (x == "tov") min(vals, na.rm = TRUE) else max(vals, na.rm = TRUE)) {
            list(background = "lightgreen", fontWeight = "bold")
          }
        })
      })
      col_fmt[["xl_at_count"]] <- colDef(show = FALSE)
      col_fmt[["Weak At"]] <- colDef(style = list(fontSize = "80%", whiteSpace = "pre-line"))
      col_fmt[["Excels At"]] <- colDef(style = \(val, ix) {
        xl_at <- df$xl_at_count[ix]
        if (xl_at == 1) {
          list(background = "#00CDCD", fontSize = "80%", whiteSpace = "pre-line")
        } else if (xl_at == 2) {
          list(background = "#8DEEEE", fontSize = "80%", whiteSpace = "pre-line")
        } else if (xl_at == 3) {
          list(background = "#00FFFF", fontSize = "80%", whiteSpace = "pre-line")
        } else {
          list(fontSize = "80%", whiteSpace = "pre-line")
        }
      })
      col_fmt[["inj_status"]] <- colDef(show = FALSE)
      col_fmt[["player_id"]] <- colDef(show = FALSE)
      col_fmt[["player"]] <- colDef(style = \(value, index) {
        status <- replace_na(df[["inj_status"]][index], "Available")
        if (status == "Out") {
          list(background = "#f51e1eff")
        } else if (status == "Questionable") {
          list(background = "#ffa87fff")
        } else if (status == "Probable") {
          list(background = "#fbff7fff")
        } else {
          list(background = "#ffffffff")
        }
      })

      reactable(
        df,
        pagination = FALSE,
        bordered = TRUE,
        highlight = TRUE,
        defaultSorted = rv_tbl_sort_order(),
        defaultSortOrder = "desc",
        defaultColDef = colDef(
          align = "left",
          minWidth = 120,
          headerStyle = list(background = "#cce5ff"),
          format = colFormat(digits = 1)
        ),
        columns = col_fmt,
        onClick = "expand",
        details = \(ix) {
          pl_tm <- if (input$log_inj_toggle) df$player[ix] else df$team[ix]
          pl_id <- df$player_id[ix]
          pl_or_tm_hf_header <- paste(if (input$log_inj_toggle) "Player" else "Team", "not found...")
          log_or_inj_header <- str_c(
            pl_tm,
            if (input$log_inj_toggle) "Game Log" else paste("Last", input$window, "Day Injury History"),
            sep = " "
          )

          df_log_or_inj <- if (input$log_inj_toggle) {
            pluck(
              ls_player_game_log,
              as.character(pl_id),
              .default = tibble(
                !!pl_tm := "No Games",
                game_date = as.Date(character()),
                opponent = character(),
                min = numeric()
              )
            ) |>
              select(game_date, opponent, min, any_of(cats()))
          } else {
            pluck(ls_injuries, input$window, pl_tm, .default = tibble(!!pl_tm := "No Injuries"))
          }

          if (is.na(pl_tm)) {
            tags$div(tags$h2(class = "title", pl_or_tm_hf_header))
          } else {
            tags$div(
              style = "margin-left: 45px; margin-top: 10px; margin-bottom: 30px;",
              tags$h2(class = "title", log_or_inj_header),
              reactable(
                df_log_or_inj,
                pagination = TRUE,
                defaultPageSize = 5,
                fullWidth = FALSE,
                defaultColDef = colDef(
                  align = "left",
                  minWidth = 120,
                  headerStyle = list(background = "#cce5ff"),
                ),
                columns = list(player_names = colDef(minWidth = 1000))
              )
            )
          }
        }
      )
    })
  })
}
## To be copied in the UI
# mod_player_comparison_ui("player_comparison_1")

## To be copied in the server
# mod_player_comparison_server("player_comparison_1")

# library(shiny)
# library(bslib)
# library(reactable)
# library(stringr)
# library(rlang)
# library(purrr)
# library(dplyr)
# library(tibble)
# library(tidyr)
# library(shinyWidgets)
# library(later)
# library(glue)

# load("data/dfs_player_comparison.rda")
# load("data/ls_lo_lg_cats.rda")
# load("data/ls_nba_teams.rda")
# load("data/ls_injuries.rda")
# load("data/ls_player_game_log.rda")

# ui <- page_fluid(
#   mod_player_comparison_ui("player_comparison_1")
# )

# server <- function(input, output, session) {
#   rv_carry_thru <- reactiveValues(
#     fty_parameters_met = TRUE,
#     platform = "ESPN",
#     league_id = 1382487116,
#     competitor_id = 6,
#     competitor_name = "britney_spears",
#     cur_matchup_period = 11
#   )

#   mod_player_comparison_server("player_comparison_1", rv_carry_thru, reactiveVal(c("ATL" = 1610612737)))
# }

# shinyApp(ui, server)
