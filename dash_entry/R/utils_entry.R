#' Current season
#'
#' @return The season string, from [core::nba_season()].
#' @export
entry_season <- function() {
  core::nba_season()
}

#' Open the entry point's database connection
#'
#' Prefers individual `NBA_DB_*` environment variables (for hosted runtimes such
#' as Hugging Face Spaces, where no credentials file exists), falling back to
#' `core::db_connect()` (INI-based) for local development.
#'
#' @return A `DBIConnection`.
#' @export
entry_db_connect <- function() {
  if (nzchar(Sys.getenv("NBA_DB_HOST"))) {
    return(DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("NBA_DB_HOST"),
      port = Sys.getenv("NBA_DB_PORT", "26257"),
      user = Sys.getenv("NBA_DB_USER"),
      password = Sys.getenv("NBA_DB_PASSWORD"),
      dbname = Sys.getenv("NBA_DB_NAME", "nba"),
      sslmode = Sys.getenv("NBA_DB_SSLMODE", "require")
    ))
  }
  core::db_connect()
}

#' Verify a customer's credentials against the database
#'
#' Looks the customer up by email and checks the password against
#' `fty.customer.password_hash`. Returns `NA` when the email is unknown or no
#' password is set, so callers can then try [dev_login()].
#'
#' @param con A `DBIConnection`.
#' @param email,password Submitted login.
#' @return The matching `customer_id`, or `NA_character_`.
#' @export
check_credentials <- function(con, email, password) {
  if (!nzchar(email) || !nzchar(password)) {
    return(NA_character_)
  }

  cols <- DBI::dbGetQuery(
    con,
    "select column_name from information_schema.columns
     where table_schema = 'fty' and table_name = 'customer'"
  )$column_name
  hash_expr <- if ("password_hash" %in% cols) "password_hash" else "null::text as password_hash"

  row <- DBI::dbGetQuery(
    con,
    sprintf(
      "select customer_id, %s from fty.customer where lower(email) = lower(%s) limit 1",
      hash_expr,
      DBI::dbQuoteString(con, email)
    )
  )
  if (nrow(row) == 0) {
    return(NA_character_)
  }

  hash <- row$password_hash[[1]]
  if (is.na(hash) || !nzchar(hash)) {
    return(NA_character_)
  }

  if (isTRUE(core::verify_password(password, hash))) {
    as.character(row$customer_id[[1]])
  } else {
    NA_character_
  }
}

#' Development login fallback
#'
#' Only active when `NBA_ENTRY_DEV=1`. Accepts any known customer email with the
#' password in `NBA_ENTRY_DEV_PASSWORD` (default `"dev"`). Intended for local
#' development and for customers whose `password_hash` is not set yet.
#'
#' @inheritParams check_credentials
#' @return The matching `customer_id`, or `NA_character_`.
#' @export
dev_login <- function(email, password, con) {
  if (Sys.getenv("NBA_ENTRY_DEV", "0") != "1") {
    return(NA_character_)
  }
  if (!identical(password, Sys.getenv("NBA_ENTRY_DEV_PASSWORD", "dev"))) {
    return(NA_character_)
  }

  row <- DBI::dbGetQuery(
    con,
    sprintf(
      "select customer_id from fty.customer where lower(email) = lower(%s) limit 1",
      DBI::dbQuoteString(con, email)
    )
  )

  if (nrow(row) == 0) NA_character_ else as.character(row$customer_id[[1]])
}

#' Customer display name
#'
#' @param con A `DBIConnection`.
#' @param customer_id Customer id.
#' @return A string.
#' @export
get_customer_name <- function(con, customer_id) {
  row <- DBI::dbGetQuery(
    con,
    sprintf(
      "select name, email from fty.customer where customer_id = %s limit 1",
      DBI::dbQuoteString(con, customer_id)
    )
  )
  if (nrow(row) == 0) {
    return(customer_id)
  }
  if (nzchar(row$name[[1]]) && !is.na(row$name[[1]])) row$name[[1]] else row$email[[1]]
}

#' Leagues a customer belongs to
#'
#' Reads `fty.customer_league`, joined to `fty.league` for names. Includes the
#' customer's `competitor_id` when that column exists on `customer_league`
#' (otherwise `NA`, and the manager must be chosen separately). Also surfaces
#' `fty.league.slug` / `container_url` / `is_active` when those columns exist,
#' so container URLs can be driven by the registry rather than the naming
#' convention, and inactive leagues are skipped.
#'
#' @param con A `DBIConnection`.
#' @param customer_id Customer id.
#' @param season Season string.
#' @return A data frame with `platform`, `league_id`, `league_name`,
#'   `competitor_id`, `slug`, `container_url`.
#' @export
get_customer_leagues <- function(con, customer_id, season = entry_season()) {
  cols <- DBI::dbGetQuery(
    con,
    "select column_name from information_schema.columns
     where table_schema = 'fty' and table_name = 'customer_league'"
  )$column_name
  competitor_col <- if ("competitor_id" %in% cols) {
    "cl.competitor_id::text as competitor_id"
  } else {
    "null::text as competitor_id"
  }

  league_cols <- DBI::dbGetQuery(
    con,
    "select column_name from information_schema.columns
     where table_schema = 'fty' and table_name = 'league'"
  )$column_name
  slug_expr <- if ("slug" %in% league_cols) "lg.slug::text as slug" else "null::text as slug"
  url_expr <- if ("container_url" %in% league_cols) "lg.container_url::text as container_url" else "null::text as container_url"
  active_clause <- if ("is_active" %in% league_cols) "and coalesce(lg.is_active, true)" else ""

  DBI::dbGetQuery(
    con,
    sprintf(
      "select cl.platform, cl.league_id::text as league_id, lg.league_name,
              %s, %s, %s
       from fty.customer_league cl
       left join fty.league lg
         on lg.season = cl.season and lg.platform = cl.platform and lg.league_id = cl.league_id
       where cl.customer_id = %s and cl.season = %s %s
       order by lg.league_name",
      competitor_col,
      slug_expr,
      url_expr,
      DBI::dbQuoteString(con, customer_id),
      DBI::dbQuoteString(con, season),
      active_clause
    )
  )
}

#' Managers (competitors) in a league
#'
#' @param con A `DBIConnection`.
#' @param platform,league_id League identity.
#' @param season Season string.
#' @return A data frame with `competitor_id`, `competitor_name`.
#' @export
get_league_competitors <- function(con, platform, league_id, season = entry_season()) {
  DBI::dbGetQuery(
    con,
    sprintf(
      "select competitor_id::text as competitor_id, competitor_name
       from fty.league_competitor
       where platform = %s and league_id = %s and season = %s
       order by competitor_name",
      DBI::dbQuoteString(con, platform),
      DBI::dbQuoteString(con, as.character(league_id)),
      DBI::dbQuoteString(con, season)
    )
  )
}

#' League container URL
#'
#' Derives the Hugging Face Space URL for a league container from the deploy
#' naming convention, e.g. `espn-95537` under owner `shaggycamel` becomes
#' `https://shaggycamel-espn-95537.hf.space`.
#'
#' @param platform,league_id League identity.
#' @param owner,prefix Overridable via `NBA_HF_OWNER` / `NBA_HF_SPACE_PREFIX`.
#' @return A URL string.
#' @export
league_space_url <- function(
  platform,
  league_id,
  owner = Sys.getenv("NBA_HF_OWNER", "shaggycamel"),
  prefix = Sys.getenv("NBA_HF_SPACE_PREFIX", "")
) {
  slug <- tolower(paste0(platform, "-", league_id))
  # The prefix is optional: with it, <owner>-<prefix>-<slug>; without, <owner>-<slug>.
  # Built with paste() rather than a fixed format string so an empty prefix cannot
  # leave a doubled hyphen.
  stem <- if (nzchar(prefix)) paste(owner, prefix, slug, sep = "-") else paste(owner, slug, sep = "-")
  sprintf("https://%s.hf.space", stem)
}

#' Signed league iframe URL
#'
#' @param space_url League container URL (see [league_space_url()]).
#' @param customer_id,platform,league_id,competitor_id Bound into the token.
#' @param ttl Token lifetime in seconds.
#' @param now Current time, for testability.
#' @param secret HMAC secret (defaults to `NBA_HANDOFF_SECRET`).
#' @return A URL with a signed query string.
#' @export
league_iframe_url <- function(
  space_url,
  customer_id,
  platform,
  league_id,
  competitor_id,
  ttl = 300,
  secret = core::handoff_secret(),
  now = Sys.time()
) {
  query <- handoff_query(
    customer_id = customer_id,
    platform = platform,
    league_id = league_id,
    competitor_id = competitor_id,
    ttl = ttl,
    secret = secret,
    now = now
  )
  paste0(space_url, "/?", query)
}

#' Parse a league select value
#'
#' League values are encoded as `"<platform>:<league_id>"` so ids that collide
#' across platforms stay distinct.
#'
#' @param value Encoded value.
#' @return A list with `platform` and `league_id`.
#' @export
parse_league_value <- function(value) {
  parts <- strsplit(value, ":", fixed = TRUE)[[1]]
  list(platform = parts[[1]], league_id = as.integer(parts[[2]]))
}

#' Browser origins of a customer's league containers
#'
#' The embedded dashboards post requests back to the entry point, which accepts
#' them only from the container origins it actually embeds.
#'
#' @param leagues Result of [get_customer_leagues()].
#' @return A character vector of origins.
#' @noRd
entry_allowed_origins <- function(leagues) {
  if (nrow(leagues) == 0L) {
    return(character(0))
  }

  urls <- ifelse(
    !is.na(leagues$container_url) & nzchar(leagues$container_url),
    leagues$container_url,
    league_space_url(leagues$platform, leagues$league_id)
  )
  unique(sub("/+$", "", urls))
}
