testServer(
  mod_modal_alter_team_server,
  # Add here your module params
  args = list(),
  {
    ns <- session$ns
    expect_true(
      inherits(ns, "function")
    )
    expect_true(
      grepl(id, ns(""))
    )
    expect_true(
      grepl("test", ns("test"))
    )
    # Here are some examples of tests you can
    # run on your module
    # - Testing the setting of inputs
    # session$setInputs(x = 1)
    # expect_true(input$x == 1)
    # - If ever your input updates a reactiveValues
    # - Note that this reactiveValues must be passed
    # - to the testServer function via args = list()
    # expect_true(r$x == 1)
    # - Testing output
    # expect_true(inherits(output$tbl$html, "html"))
  }
)

test_that("module ui works", {
  ui <- mod_modal_alter_team_ui(id = "test")
  golem::expect_shinytaglist(ui)
  # Check that formals have not been removed
  fmls <- formals(mod_modal_alter_team_ui)
  for (i in c("id")) {
    expect_true(i %in% names(fmls))
  }
})

test_that("an add with FA unticked uses the full player list", {
  rv_alter_team <- reactiveVal(list())
  modal_vals <- reactiveValues(
    ui_date = Sys.Date(),
    mup_end_date = Sys.Date() + 6,
    free_agents = c("FA One" = 1L),
    all_players = c("FA One" = 1L, "Rival Guy" = 2L),
    roster = c("Mine" = 3L)
  )
  trigger <- reactiveVal(0L)

  testServer(
    mod_modal_alter_team_server,
    args = list(
      rv_alter_team = rv_alter_team,
      rv_alter_team_modal_vals = modal_vals,
      rv_alter_team_trigger = trigger
    ),
    {
      trigger(1L)
      session$setInputs(
        add_or_exclude = TRUE,
        free_agent_filter = FALSE,
        action_date = Sys.Date(),
        player = "2"
      )
      session$setInputs(proceed = 1)

      expect_equal(names(rv_alter_team()), "add-Rival Guy")
      expect_equal(rv_alter_team()[["add-Rival Guy"]]$player_id, 2L)
    }
  )
})

test_that("an add with FA ticked keeps the free-agent list", {
  rv_alter_team <- reactiveVal(list())
  modal_vals <- reactiveValues(
    ui_date = Sys.Date(),
    mup_end_date = Sys.Date() + 6,
    free_agents = c("FA One" = 1L),
    all_players = c("FA One" = 1L, "Rival Guy" = 2L),
    roster = c("Mine" = 3L)
  )
  trigger <- reactiveVal(0L)

  testServer(
    mod_modal_alter_team_server,
    args = list(
      rv_alter_team = rv_alter_team,
      rv_alter_team_modal_vals = modal_vals,
      rv_alter_team_trigger = trigger
    ),
    {
      trigger(1L)
      session$setInputs(
        add_or_exclude = TRUE,
        free_agent_filter = TRUE,
        action_date = Sys.Date(),
        player = "1"
      )
      session$setInputs(proceed = 1)

      expect_equal(names(rv_alter_team()), "add-FA One")
    }
  )
})

test_that("several players can be added or excluded in one go", {
  rv_alter_team <- reactiveVal(list())
  modal_vals <- reactiveValues(
    ui_date = Sys.Date(),
    mup_end_date = Sys.Date() + 6,
    free_agents = c("FA One" = 1L),
    all_players = c("FA One" = 1L, "Rival Guy" = 2L),
    roster = c("Mine" = 3L, "Other" = 4L)
  )
  trigger <- reactiveVal(0L)

  testServer(
    mod_modal_alter_team_server,
    args = list(
      rv_alter_team = rv_alter_team,
      rv_alter_team_modal_vals = modal_vals,
      rv_alter_team_trigger = trigger
    ),
    {
      trigger(1L)
      session$setInputs(
        add_or_exclude = TRUE,
        free_agent_filter = FALSE,
        action_date = Sys.Date(),
        player = c("1", "2")
      )
      session$setInputs(proceed = 1)

      expect_setequal(names(rv_alter_team()), c("add-FA One", "add-Rival Guy"))

      session$setInputs(add_or_exclude = FALSE)
      session$setInputs(player = c("3", "4"))
      session$setInputs(proceed = 2)

      expect_setequal(
        names(rv_alter_team()),
        c("add-FA One", "add-Rival Guy", "ex-Mine", "ex-Other")
      )
    }
  )
})
