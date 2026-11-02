# base_data_prep() stitches a matchup together from the past and future package
# data, then applies any add/drop moves the user made this matchup. The data
# comes from three package objects, so the tests mock them with a small league
# rather than relying on the committed season.

base_fixtures <- function() {
  list(
    # league -> matchup -> competitor -> games
    past = list(
      "1" = list(
        "5" = list(
          "1" = tibble(
            player_id = 10L,
            game_date = cur_date - 2,
            pts = 5,
            scheduled_to_play = 1
          ),
          "2" = tibble(
            player_id = 20L,
            game_date = cur_date - 2,
            pts = 7,
            scheduled_to_play = 1
          )
        )
      )
    ),
    # league -> matchup -> competitor -> window -> games
    future = list(
      "1" = list(
        "5" = list(
          "1" = list(
            "7" = tibble(
              player_id = c(10L, 11L),
              game_date = c(cur_date + 1, cur_date + 2),
              pts = c(3, 4),
              scheduled_to_play = 1,
              matchup_start = cur_date - 1,
              matchup_end = cur_date + 3
            )
          ),
          "2" = list(
            "7" = tibble(
              player_id = 20L,
              game_date = cur_date + 1,
              pts = 6,
              scheduled_to_play = 1,
              matchup_start = cur_date - 1,
              matchup_end = cur_date + 3
            )
          )
        ),
        "6" = list(
          "1" = list(
            "7" = tibble(
              player_id = 10L,
              game_date = cur_date + 8,
              pts = 3,
              scheduled_to_play = 1,
              matchup_start = cur_date + 7,
              matchup_end = cur_date + 13
            )
          ),
          "2" = list(
            "7" = tibble(
              player_id = 20L,
              game_date = cur_date + 8,
              pts = 6,
              scheduled_to_play = 1,
              matchup_start = cur_date + 7,
              matchup_end = cur_date + 13
            )
          )
        ),
        # Free agents are stored under a "free_agent" matchup, not a real one.
        # Their dates span the rest of the season in the built data.
        "free_agent" = list(
          "free_agent" = list(
            "7" = tibble(
              player_id = 30L,
              game_date = c(cur_date + 2, cur_date + 4, cur_date + 10),
              pts = c(2, 1, 9),
              scheduled_to_play = 1,
              matchup_start = cur_date - 1,
              matchup_end = cur_date + 100
            )
          )
        )
      )
    ),
    lookup = list(cp_id_to_name = list("1" = c("1" = "Me", "2" = "Rival")))
  )
}

base_input <- function(future_only = TRUE) {
  list(future_only = future_only, matchup = "5", window = "7")
}

base_rv <- function() {
  list(league_id = 1, competitor_id = 1, cur_matchup_period = 5)
}

base_opponent <- function(id = 2, name = "Rival") {
  function() list(id = id, name = name)
}

base_prep <- function(input, rv_carry_thru, opponent, rv_alter_team) {
  fixtures <- base_fixtures()
  local_pkg_data(
    dfs_h2h_past = fixtures$past,
    dfs_h2h_future = fixtures$future,
    ls_fty_lookup = fixtures$lookup
  )
  base_data_prep(input, rv_carry_thru, opponent, rv_alter_team)
}

test_that("future_only leaves the past out entirely", {
  out <- base_prep(base_input(future_only = TRUE), base_rv(), base_opponent(), list())

  expect_setequal(out$tense, "future")
  expect_setequal(out$player_id, c(10L, 11L, 20L))
})

test_that("past and future rows are tagged and both competitors appear", {
  out <- base_prep(base_input(future_only = FALSE), base_rv(), base_opponent(), list())

  expect_setequal(out$tense, c("past", "future"))
  # Me first, then the opponent, as an ordered factor for the plots.
  expect_equal(levels(out$competitor), c("Me", "Rival"))
  expect_identical(
    filter(out, tense == "past")$player_id,
    c(20L, 10L)
  )
})

test_that("a bye shows only the competitor's own team", {
  out <- base_prep(
    base_input(),
    base_rv(),
    base_opponent(id = NA, name = NA_character_),
    list()
  )

  expect_equal(unique(as.character(out$competitor)), "Me")
  expect_setequal(out$player_id, c(10L, 11L))
})

test_that("a drop keeps the player's row but excludes their remaining games", {
  moves <- list(list(
    action = "ex",
    player_id = 10L,
    action_date = as.character(cur_date)
  ))
  out <- base_prep(base_input(), base_rv(), base_opponent(), moves)
  dropped <- filter(out, competitor == "Me", player_id == 10L)

  expect_equal(nrow(dropped), 1L)
  expect_true(dropped$excluded)
  expect_equal(dropped$scheduled_to_play, 0)
  expect_false(any(filter(out, player_id == 11L)$excluded))
  # The opponent's side is untouched.
  expect_true(20L %in% filter(out, competitor == "Rival")$player_id)
  expect_false(any(filter(out, competitor == "Rival")$excluded))
})

test_that("a drop only excludes games from the action date onward", {
  moves <- list(list(
    action = "ex",
    player_id = 10L,
    action_date = as.character(cur_date)
  ))
  out <- base_prep(
    base_input(future_only = FALSE),
    base_rv(),
    base_opponent(),
    moves
  )
  dropped <- filter(out, player_id == 10L) |>
    arrange(game_date)

  expect_equal(dropped$excluded, c(FALSE, TRUE))
  expect_equal(dropped$scheduled_to_play, c(1, 0))
})

test_that("an add brings a free agent's games into the current matchup", {
  moves <- list(list(
    action = "add",
    player_id = 30L,
    action_date = as.character(cur_date)
  ))
  out <- base_prep(base_input(), base_rv(), base_opponent(), moves)

  expect_true(30L %in% filter(out, competitor == "Me")$player_id)
})

test_that("an added free agent is confined to the current matchup", {
  moves <- list(list(
    action = "add",
    player_id = 30L,
    action_date = as.character(cur_date)
  ))
  out <- base_prep(base_input(), base_rv(), base_opponent(), moves)
  fa <- filter(out, player_id == 30L)

  expect_equal(nrow(fa), 2L)
  expect_equal(fa$matchup_start, c(cur_date - 1, cur_date - 1))
  expect_equal(fa$matchup_end, c(cur_date + 3, cur_date + 3))
  expect_equal(fa$matchup_end_plus, c(NA, cur_date + 5))
})

test_that("an add persists into later matchups without earlier games leaking in", {
  input <- base_input()
  input$matchup <- "6"
  moves <- list(list(
    action = "add",
    player_id = 30L,
    action_date = as.character(cur_date)
  ))
  out <- base_prep(input, base_rv(), base_opponent(), moves)
  fa <- filter(out, player_id == 30L)

  expect_equal(fa$game_date, cur_date + 10)
  expect_equal(fa$matchup_start, cur_date + 7)
  expect_true(all(fa$game_date >= fa$matchup_start))
})

test_that("a move dated before today has already been applied and is ignored", {
  moves <- list(list(
    action = "ex",
    player_id = 10L,
    action_date = as.character(cur_date - 1)
  ))
  out <- base_prep(base_input(), base_rv(), base_opponent(), moves)

  expect_true(10L %in% filter(out, competitor == "Me")$player_id)
  expect_false(any(out$excluded))
})
