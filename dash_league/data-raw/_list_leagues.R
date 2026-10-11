# List leagues to build ------------------------------------------------
# Emits "platform,league_id,slug" (one per line) for the current season, so the
# deploy scripts do not need psql or a DATABASE_URL — R + the credentials INI
# are enough. Uses fty.league.slug / is_active when those columns exist.

source(here::here("data-raw", "_setup.R"))
source(here::here("R", "utils_database.R"))

season <- core::nba_season()
con <- db_connect(Sys.getenv("NBA_DB_SECTION", "cockroach-read"))
on.exit(DBI::dbDisconnect(con), add = TRUE)

cols <- DBI::dbGetQuery(
  con,
  "select column_name from information_schema.columns
   where table_schema = 'fty' and table_name = 'league'"
)$column_name

slug_expr <- if ("slug" %in% cols) "slug::text" else "null::text"
active_clause <- if ("is_active" %in% cols) "and coalesce(is_active, true)" else ""

df <- DBI::dbGetQuery(
  con,
  sprintf(
    "select platform, league_id, %s as slug
     from fty.league where season = %s %s order by league_id",
    slug_expr,
    DBI::dbQuoteString(con, season),
    active_clause
  )
)

out <- paste(df$platform, df$league_id, ifelse(is.na(df$slug), "", df$slug), sep = ",")
cat(out, sep = "\n")
if (length(out)) {
  cat("\n")
}
