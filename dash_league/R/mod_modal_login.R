#' login_modal Server Functions
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
mod_modal_login_ui <- function(id) {
  ns <- NS(id)

  tagList(
    fluidPage(ns("blank_page"))
  )
}

#' @noRd
#'
mod_modal_login_server <- function(
  id,
  rv_carry_thru,
  rv_switch_league_counter,
  rv_alter_team,
  rv_snapshot_log,
  rv_snapshot_trigger
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    observe({
      if (input$fty_league_select != "") {
        .league_name <- input$fty_league_select
        league_id <- pluck(ls_fty_lookup, "lg_name_to_id", .league_name)

        rv_carry_thru$league_name <- .league_name
        rv_carry_thru$league_id <- league_id
        rv_carry_thru$platform <- pluck(ls_fty_lookup, "lg_id_to_platform", as.character(league_id))
        rv_carry_thru$cur_matchup_period <- pluck(dfs_fty_schedule, as.character(league_id)) |>
          filter(matchup_start <= cur_date, matchup_end >= cur_date) |>
          pull(matchup_period) |>
          pluck(1)

        # The manager is derived from the league (the customer mapping is
        # authoritative); take the league's first competitor as the default.
        competitor <- df_fty_base |>
          filter(league_name == .league_name) |>
          arrange(competitor_name)
        rv_carry_thru$competitor_name <- competitor$competitor_name[[1]]
        rv_carry_thru$competitor_id <- competitor$competitor_id[[1]]

        rv_carry_thru$fty_parameters_met <- TRUE
        removeModal()
        output$login_messages <- NULL
      } else {
        output$login_messages <- renderText("Select a league...")
      }
    }) |>
      bindEvent(input$fty_dash_init, ignoreInit = TRUE)

    # Gotta fill the form at least once!
    observe({
      if (!!rv_carry_thru$fty_parameters_met) {
        output$login_messages <- renderText("You gotta go fill the form at least once!")
      } else {
        removeModal()
        output$login_messages <- NULL
      }
    }) |>
      bindEvent(input$fty_abort)

    # Modal UI structure.
    observe({
      # Embedded via the entry point: the manager is already set, skip the modal.
      if (isTRUE(rv_carry_thru$handoff_active)) {
        return()
      }

      # Strict mode: no token means no dashboard.
      if (isTRUE(rv_carry_thru$handoff_required)) {
        showModal(
          modalDialog(
            tags$h4("Sign in required"),
            "Open this dashboard from the entry point.",
            easyClose = FALSE,
            footer = NULL
          )
        )
        return()
      }

      showModal(
        modalDialog(
          tags$head(tags$style(HTML(".selectize-dropdown-content{min-width: 100%; box-sizing: border-box;}"))),

          # Select League
          selectizeInput(
            ns("fty_league_select"),
            label = NULL,
            choices = unique(df_fty_base$league_name),
            options = list(
              placeholder = "Select Fantasy League",
              onInitialize = I("function(){this.setValue('');}")
            ),
            width = "100%"
          ),

          span(textOutput(ns("login_messages")), style = "color:red"),
          footer = tagList(
            actionButton(
              ns("fty_abort"),
              label = NULL,
              icon = icon("square-xmark"),
              style = "color:#FFF; background-color:#CD3333; border-color:#2E6DA4"
            ),
            actionButton(
              ns("fty_dash_init"),
              "Kobeee!",
              style = "color:#FFF; background-color:#337AB7; border-color:#2E6DA4"
            )
          ),
          size = "m"
        )
      )
    }) |>
      bindEvent(rv_switch_league_counter(), ignoreNULL = FALSE, ignoreInit = FALSE)
  })
}

## To be copied in the server
# mod_modal_login_server("modal_login_1")
