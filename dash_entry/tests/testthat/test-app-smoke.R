# End-to-end smoke test: boots the entry-point server against the local
# postgres, logs in (dev mode), chooses a league and builds a signed iframe URL.
# Skips when no local database is reachable.

local_db_up <- function() {
  con <- tryCatch(core::db_connect("postgres"), error = function(e) NULL)
  if (is.null(con)) {
    return(FALSE)
  }
  DBI::dbDisconnect(con)
  TRUE
}

with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA)
  do.call(Sys.setenv, vars)
  on.exit(
    for (nm in names(vars)) {
      if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(old[[nm]]), nm))
    },
    add = TRUE
  )
  force(code)
}

test_that("entry app boots, logs in and builds a signed iframe", {
  skip_if_not(local_db_up(), "no local postgres available")

  with_env(
    list(
      NBA_DB_SECTION = "postgres",
      NBA_ENTRY_DEV = "1",
      NBA_ENTRY_DEV_PASSWORD = "dev",
      NBA_HANDOFF_SECRET = "test-secret",
      NBA_ENTRY_CREDENTIALS = ""
    ),
    {
      shiny::testServer(app_server, {
        session$setInputs(email = "eat_fred@proton.me", password = "dev")
        session$setInputs(login = 1)

        df <- leagues()
        expect_gt(nrow(df), 0L)

        # A customer with several leagues chooses one from the switcher.
        session$setInputs(league_choice = "ESPN:95537")
        session$setInputs(league_choose_confirm = 1)

        html <- paste(as.character(output$iframe), collapse = "")
        expect_match(html, "hf.space")
        expect_match(html, "sig=")

        src <- regmatches(html, regexpr("https://[^\"]+", html))
        expect_length(src, 1L)
        src <- gsub("&amp;", "&", src, fixed = TRUE)
        params <- shiny::parseQueryString(sub("^[^?]*\\?", "", src))
        expect_true(core::verify_handoff_token(
          params$sig, params$customer_id, params$platform, params$league_id,
          params$competitor_id, params$exp
        ))
      })
    }
  )
})
