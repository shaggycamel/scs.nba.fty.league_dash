# Dashboard-update audit log ------------------------------------------------
# Appends one row per dashboard deploy event to util.update_log, the same table
# the database repo's __main__.py writes. Rows are namespaced ('dashboard:*')
# so they never collide with the database's per-table rows. Writes are
# best-effort: a failed write warns and returns FALSE rather than aborting the
# deploy. The run's cadence ('daily'/'intraday'/'all') mirrors database/cron.sh.
# source names the writing repo; job_kickoff is the run's start, shared by every
# row of that run (so a run can be grouped).

#' Assemble one util.update_log row
#'
#' Kept separate from the write so the row shape can be tested without a
#' database. Column order matches util.update_log:
#' `task, task_time, cadence, success, error_message, source, job_kickoff`.
#'
#' @param task Task name, e.g. `"dashboard:espn-95537"`.
#' @param success Whether the event succeeded.
#' @param error Optional error text; `NULL` (the default) for a success.
#' @param cadence Run cadence marker; defaults to `"all"`.
#' @param task_time Timestamp for `task_time`; defaults to now.
#' @param source Which repo wrote the row; `NA` when unset.
#' @param job_kickoff When the run started (same for every row of a run); `NULL`
#'   when unset.
#'
#' @return A one-row `data.frame`.
#' @noRd
update_log_row <- function(
  task,
  success,
  error = NULL,
  cadence = "all",
  task_time = Sys.time(),
  source = NA_character_,
  job_kickoff = NULL
) {
  if (!is.character(task) || length(task) != 1L || is.na(task) || !nzchar(task)) {
    stop("task must be a single non-empty string", call. = FALSE)
  }
  if (is.null(cadence) || length(cadence) != 1L || is.na(cadence) || !nzchar(cadence)) {
    cadence <- "all"
  }
  error_chr <- if (is.null(error) || length(error) == 0L) {
    NA_character_
  } else {
    as.character(error[[1L]])
  }
  error_message <- if (
    length(error_chr) == 1L && !is.na(error_chr) && nzchar(error_chr)
  ) {
    error_chr
  } else {
    NA_character_
  }
  source <- if (is.null(source) || length(source) == 0L || is.na(source[[1L]])) {
    NA_character_
  } else {
    as.character(source[[1L]])
  }
  job_kickoff <- if (is.null(job_kickoff) || length(job_kickoff) == 0L || is.na(job_kickoff[[1L]])) {
    as.POSIXct(NA_character_, tz = "UTC")
  } else {
    as.POSIXct(job_kickoff[[1L]])
  }

  data.frame(
    task = task,
    task_time = as.POSIXct(task_time),
    cadence = cadence,
    success = isTRUE(success),
    error_message = error_message,
    source = source,
    job_kickoff = job_kickoff,
    stringsAsFactors = FALSE
  )
}

#' Log a dashboard update to util.update_log
#'
#' Appends one row to `util.update_log`. Best-effort: any connection or write
#' error is caught, warned about, and returned as `FALSE` so a logging hiccup
#' never fails the deploy.
#'
#' @param task Task name, e.g. `"dashboard:espn-95537"`.
#' @param success Whether the event succeeded.
#' @param error Optional error text (a short stage + reason) for a failure.
#' @param cadence Run cadence marker. Defaults to the `DEPLOY_CADENCE`
#'   environment variable, or `"all"`.
#' @param source Which repo wrote the row. Defaults to the `UPDATE_LOG_SOURCE`
#'   environment variable, or `"scs.nba.fty.league_dash"`.
#' @param job_kickoff When the run started, shared by every row of the run.
#' @param section Credentials INI section to write with. Defaults to the
#'   `NBA_UPDATE_LOG_SECTION` environment variable, or `"cockroach-write"`.
#'
#' @return `TRUE` when the row was written, `FALSE` otherwise.
#' @export
log_update <- function(
  task,
  success,
  error = NULL,
  cadence = Sys.getenv("DEPLOY_CADENCE", "all"),
  source = Sys.getenv("UPDATE_LOG_SOURCE", "scs.nba.fty.league_dash"),
  job_kickoff = NULL,
  section = Sys.getenv("NBA_UPDATE_LOG_SECTION", "cockroach-write")
) {
  row <- update_log_row(
    task,
    success,
    error = error,
    cadence = cadence,
    source = source,
    job_kickoff = job_kickoff
  )

  tryCatch(
    {
      con <- db_connect(section)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      DBI::dbWriteTable(
        con,
        DBI::Id(schema = "util", table = "update_log"),
        row,
        append = TRUE
      )
      TRUE
    },
    error = function(e) {
      warning(
        "could not write util.update_log row for ", task, ": ", conditionMessage(e),
        call. = FALSE
      )
      FALSE
    }
  )
}
