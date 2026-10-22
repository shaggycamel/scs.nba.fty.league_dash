# League fantasy data layer -------------------------------------------------
# League-scoped and customer-agnostic; run once per league container (control
# the target with LEAGUE_ID in 03_fty_base.R). Loads the shared base cache when
# the base layer has not already been generated in this session.

source(here::here("data-raw", "_setup.R"))
source(here::here("R", "utils_database.R"))
source(here::here("R", "utils_calc_z_pcts.R"))
source(here::here("R", "utils_h2h.R"))
db_con <- db_connect(Sys.getenv("NBA_DB_SECTION", "cockroach-read"))

source(here::here("data-raw", "01_constants.R"))

if (!exists("dfs_rolling_stats", inherits = FALSE)) {
  base_cache <- here::here("data-raw", "cache", "base.rda")
  if (!file.exists(base_cache)) {
    stop("Shared base cache not found; run _generate_base.R first")
  }
  load(base_cache)
}

# Shared runtime objects ship with every league container's app data.
usethis::use_data(ls_nba_teams, ls_injuries, ls_player_game_log, overwrite = TRUE)

source(here::here("data-raw", "03_fty_base.R"))
source(here::here("data-raw", "data_h2h.R"))
source(here::here("data-raw", "data_league_overview.R"))
source(here::here("data-raw", "data_player_comparison.R"))
source(here::here("data-raw", "data_schedule_table.R"))
DBI::dbDisconnect(db_con)
