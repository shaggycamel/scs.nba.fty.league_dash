#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @importFrom bslib page_navbar nav_spacer nav_panel nav_menu nav_item bs_theme
#' @importFrom shinyjs useShinyjs
#' @noRd
app_ui <- function(request) {
  tagList(
    golem_add_external_resources(),
    useShinyjs(),
    tags$head(tags$style(HTML(
      "/* Let d3 outputs fill their fillable card even when wrapped by {shinycssloaders}. */
       .card-body > .shiny-spinner-output-container {
         flex: 1 1 auto; min-height: 0;
         display: flex; flex-direction: column;
       }
       .shiny-spinner-output-container > .r2d3,
       .shiny-spinner-output-container > .reactable {
         flex: 1 1 auto; min-height: 0;
       }
       .navbar .navbar-brand {
         position: relative; line-height: 1;
       }
       .navbar .nav-last-update {
         position: absolute; left: 0; top: 100%;
         font-size: 0.7rem; font-weight: 400; opacity: 0.85; line-height: 1;
         white-space: nowrap;
       }"
    ))),
    page_navbar(
      id = "title_container",
      window_title = "NBA Fantasy",
      title = tags$div(
        uiOutput("navbar_title"),
        uiOutput("nav_last_update")
      ),
      nav_spacer(),
      nav_panel("Overview", mod_league_overview_ui("league_overview_1")),
      nav_panel("H2H", mod_h2h_ui("h2h_1")),
      nav_panel("Schedule", mod_schedule_table_ui("schedule_table_1")),
      nav_panel("Player Comparison", mod_player_comparison_ui("player_comparison_1")),
      nav_item(actionButton(
        "fty_league_competitor_switch",
        "League",
        icon = icon("right-from-bracket"),
        width = "150px",
        style = "color:#FFF; background-color:#337AB7; border-color:#2E6DA4"
      )),
      theme = core::nba_theme()
    )
  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www")
  )

  tags$head(
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "league"
    )
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}
