# ESPN's starting slots, from its lineupSlotId map: 0-11 are the starting
# line-up, 12 is bench and 13 is IR. The remaining values ('' for an unused
# slot, 'Rookie') never score.
starting_lineup_slots <- c(
  "PG",
  "SG",
  "SF",
  "PF",
  "C",
  "G",
  "F",
  "SG/SF",
  "G/F",
  "PF/C",
  "F/C",
  "UT"
)


#' Is a lineup slot one that scores?
#'
#' @description
#' TRUE for the starting slots. An unknown slot counts as starting: roster
#' snapshots taken before the slot was captured carry NA, and those weeks must
#' keep the behaviour they had - every rostered player - rather than losing
#' their stats.
#'
#' @noRd
is_starting_lineup <- function(slot) {
  is.na(slot) | slot %in% starting_lineup_slots
}


fill_free_agent_window <- function(df) {
  df |>
    mutate(
      matchup_start = replace_na(matchup_start, min(matchup_start, na.rm = TRUE)),
      matchup_end = replace_na(matchup_end, max(matchup_end, na.rm = TRUE)),
      .by = league_id
    )
}
