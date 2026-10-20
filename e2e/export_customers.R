suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

args <- commandArgs(trailingOnly = FALSE)
script_arg <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(script_arg)) {
  dirname(dirname(normalizePath(script_arg[[1]])))
} else {
  getwd()
}

source(file.path(root, "dash_core", "R", "db.R"))
source(file.path(root, "dash_core", "R", "season.R"))

con <- db_connect(Sys.getenv("NBA_DB_SECTION", "cockroach-read"))
on.exit(DBI::dbDisconnect(con), add = TRUE)

season <- nba_season()
emails <- DBI::dbGetQuery(
  con,
  sprintf(
    "select distinct c.email
       from fty.customer c
       join fty.customer_league cl
         on cl.customer_id = c.customer_id
       join fty.league lg
         on lg.season = cl.season
        and lg.platform = cl.platform
        and lg.league_id = cl.league_id
      where c.password_hash is not null
        and cl.competitor_id is not null
        and cl.season = %s
      order by c.email",
    DBI::dbQuoteString(con, season)
  )
)$email

writeLines(emails)
