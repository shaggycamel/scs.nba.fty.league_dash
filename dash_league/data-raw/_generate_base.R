# Shared NBA data layer -----------------------------------------------------
# Generated once per release. Writes a build cache (data-raw/cache/base.rda) that
# the league layer consumes, so the expensive NBA/rolling-stats work is not
# repeated per league container.

source(here::here("data-raw", "_setup.R"))
source(here::here("R", "utils_database.R"))
source(here::here("R", "utils_calc_z_pcts.R"))
db_con <- db_connect(Sys.getenv("NBA_DB_SECTION", "cockroach-read"))

source(here::here("data-raw", "01_constants.R"))
source(here::here("data-raw", "02_nba_base.R"))
DBI::dbDisconnect(db_con)
