# Log one dashboard-update event to util.update_log -------------------------
# Called by deploy/cron.sh after each deploy stage (and for the start/end
# bookends). Usage:
#
#   Rscript ./data-raw/_log_update.R <task> <ok|fail> [error message]
#
# The cadence is read from DEPLOY_CADENCE, the writing repo from
# UPDATE_LOG_SOURCE (default scs.nba.fty.league_dash), the run start from
# UPDATE_LOG_KICKOFF (ISO 8601, e.g. 2024-06-01T12:00:00Z) and the database
# section from NBA_UPDATE_LOG_SECTION (default cockroach-write). Logging is
# best-effort: this script always exits 0, and a failed write only warns, so it
# can never fail the deploy.

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2L) {
  cat(
    "usage: _log_update.R <task> <ok|fail> [error message]\n",
    file = stderr()
  )
  quit(status = 0)
}

task <- args[[1L]]
status <- args[[2L]]
error <- if (length(args) >= 3L) args[[3L]] else NULL

source <- Sys.getenv("UPDATE_LOG_SOURCE", unset = "scs.nba.fty.league_dash")
kickoff_raw <- Sys.getenv("UPDATE_LOG_KICKOFF", unset = "")
job_kickoff <- if (nzchar(kickoff_raw)) {
  as.POSIXct(kickoff_raw, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
} else {
  NULL
}

ok <- core::log_update(
  task,
  identical(status, "ok"),
  error = error,
  source = source,
  job_kickoff = job_kickoff
)

if (!ok) {
  cat("update_log write failed for ", task, "\n", sep = "", file = stderr())
}

quit(status = 0)
