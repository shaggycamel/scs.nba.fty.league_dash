season_placeholder_text <- function(season = core::nba_season(), start = NULL) {
  if (is.null(start) || length(start) == 0 || is.na(start[[1]])) {
    return(paste0(
      "The ", season, " NBA season has not started yet. ",
      "Standings and league trends will populate after the first completed matchups."
    ))
  }

  paste0(
    "The ", season, " NBA regular season starts ",
    format(as.Date(start[[1]]), "%d %B %Y"),
    ". Standings and league trends will populate after the first completed matchups."
  )
}

empty_state <- function(message) {
  htmltools::div(
    class = "text-muted p-4",
    style = "display: flex; align-items: center; justify-content: center; height: 100%; text-align: center;",
    message
  )
}

placeholder_reactable <- function(message) {
  reactable::reactable(
    tibble::tibble(message = message),
    columns = list(message = reactable::colDef(name = "")),
    pagination = FALSE,
    bordered = FALSE,
    defaultColDef = reactable::colDef(headerStyle = list(display = "none"))
  )
}
