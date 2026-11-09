#' The entry point server-side
#'
#' @param input,output,session Internal {shiny} parameters.
#' @noRd
app_server <- function(input, output, session) {
  con <- entry_db_connect()
  session$onSessionEnded(function() {
    try(DBI::dbDisconnect(con), silent = TRUE)
  })

  season <- entry_season()
  rv <- reactiveValues(customer_id = NULL, current_league = NULL)

  options(page.spinner.type = 6, page.spinner.color = "#133DEF")

  show_login <- function() {
    removeModal()
    showModal(login_modal())
  }

  show_login()

  observeEvent(input$login, {
    shinycssloaders::showPageSpinner(
      type = 6,
      color = "#133DEF",
      caption = "Signing in..."
    )

    customer_id <- check_credentials(con, input$email, input$password)
    if (is.na(customer_id)) {
      customer_id <- dev_login(input$email, input$password, con)
    }

    if (is.na(customer_id)) {
      output$login_message <- renderText("Invalid email or password")
      shinycssloaders::hidePageSpinner()
      return()
    }

    rv$customer_id <- customer_id
    output$login_message <- NULL
    removeModal()
    shinycssloaders::hidePageSpinner()
  })

  leagues <- reactive({
    req(rv$customer_id)
    get_customer_leagues(con, rv$customer_id, season)
  })

  current_league_value <- reactive({
    if (is.null(rv$current_league)) {
      NULL
    } else {
      paste(rv$current_league$platform, rv$current_league$league_id, sep = ":")
    }
  })

  # After login: a single league is loaded straight away, otherwise the customer
  # chooses from the switcher.
  observeEvent(rv$customer_id, {
    req(rv$customer_id)
    df <- leagues()
    if (nrow(df) == 1L) {
      rv$current_league <- list(
        platform = df$platform[[1]],
        league_id = as.integer(df$league_id[[1]])
      )
    } else if (nrow(df) > 1L) {
      showModal(league_chooser_modal(df, current_league_value()))
    }
  })

  # The dashboard's "League" button asks the entry to reopen the chooser.
  observeEvent(input$nba_choose, {
    req(rv$customer_id)
    showModal(league_chooser_modal(leagues(), current_league_value()))
  })

  observeEvent(input$league_choose_confirm, {
    value <- input$league_choice
    if (is.null(value) || !nzchar(value)) {
      output$league_choice_message <- renderText("Select a league...")
      return()
    }
    rv$current_league <- parse_league_value(value)
    output$league_choice_message <- NULL
    removeModal()
  })

  selected_league_row <- reactive({
    req(rv$current_league)
    df <- leagues()
    df[
      df$platform == rv$current_league$platform &
        as.integer(df$league_id) == rv$current_league$league_id,
      ,
      drop = FALSE
    ]
  })

  # The manager bound to the selected league for this customer (guaranteed set).
  mapped_competitor <- reactive({
    as.character(selected_league_row()$competitor_id[[1]])
  })

  # Prefer the registry container_url; fall back to the deploy naming convention.
  league_container_url <- reactive({
    row <- selected_league_row()
    if (
      nrow(row) == 1L && !is.null(row$container_url) && !is.na(row$container_url[[1]]) && nzchar(row$container_url[[1]])
    ) {
      row$container_url[[1]]
    } else {
      league_space_url(rv$current_league$platform, rv$current_league$league_id)
    }
  })

  output$app <- renderUI({
    if (is.null(rv$customer_id)) {
      tags$div(class = "app-frame-empty", "Sign in to view your leagues.")
    } else {
      shell_ui(leagues())
    }
  })

  output$iframe <- renderUI({
    req(rv$current_league)
    sel <- rv$current_league

    url <- league_iframe_url(
      league_container_url(),
      customer_id = rv$customer_id,
      platform = sel$platform,
      league_id = sel$league_id,
      competitor_id = mapped_competitor()
    )

    tags$iframe(
      id = "league_frame",
      src = url,
      title = "League dashboard",
      onload = "if (window.nbaHeartbeat) window.nbaHeartbeat(); if (window.Shiny) Shiny.setInputValue('iframe_loaded', Date.now(), {priority: 'event'});"
    )
  })

  # Show the spinner whenever a league is being loaded, hide it once the
  # embedded dashboard reports that it has loaded.
  observeEvent(
    rv$current_league,
    {
      req(rv$current_league)
      shinycssloaders::showPageSpinner(
        type = 6,
        color = "#133DEF",
        caption = "Loading league..."
      )
    },
    ignoreNULL = TRUE
  )

  observeEvent(input$iframe_loaded, {
    shinycssloaders::hidePageSpinner()
  })
}
