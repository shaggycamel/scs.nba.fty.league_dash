with_secret <- function(code, secret = "test-secret") {
  old <- Sys.getenv("NBA_HANDOFF_SECRET", unset = NA)
  Sys.setenv(NBA_HANDOFF_SECRET = secret)
  on.exit(
    if (is.na(old)) Sys.unsetenv("NBA_HANDOFF_SECRET") else Sys.setenv(NBA_HANDOFF_SECRET = old),
    add = TRUE
  )
  force(code)
}

now <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")
future <- as.integer(as.numeric(now) + 300)

test_that("sign then verify round-trips", {
  with_secret({
    sig <- sign_handoff_token("cus_1", "ESPN", 95537, 42, exp = future)
    expect_true(verify_handoff_token(sig, "cus_1", "ESPN", 95537, 42, exp = future, now = now))
  })
})

test_that("a token bound to one manager/customer is rejected for another", {
  with_secret({
    sig <- sign_handoff_token("cus_1", "ESPN", 95537, 42, exp = future)
    expect_false(verify_handoff_token(sig, "cus_2", "ESPN", 95537, 42, exp = future, now = now))
    expect_false(verify_handoff_token(sig, "cus_1", "ESPN", 95537, 99, exp = future, now = now))
    expect_false(verify_handoff_token(sig, "cus_1", "YAHOO", 95537, 42, exp = future, now = now))
  })
})

test_that("expired tokens are rejected", {
  with_secret({
    sig <- sign_handoff_token("cus_1", "ESPN", 95537, 42, exp = 100)
    expect_false(verify_handoff_token(sig, "cus_1", "ESPN", 95537, 42, exp = 100, now = now))
  })
})

test_that("a tampered signature is rejected", {
  with_secret({
    sig <- sign_handoff_token("cus_1", "ESPN", 95537, 42, exp = future)
    expect_false(verify_handoff_token(paste0(sig, "0"), "cus_1", "ESPN", 95537, 42, exp = future, now = now))
  })
})

test_that("the wrong secret is rejected", {
  with_secret(
    {
      sig <- sign_handoff_token("cus_1", "ESPN", 95537, 42, exp = future)
      expect_false(verify_handoff_token(sig, "cus_1", "ESPN", 95537, 42, exp = future, secret = "other", now = now))
    },
    secret = "test-secret"
  )
})

test_that("handoff_query produces a verifiable query string", {
  with_secret({
    q <- handoff_query("cus_1", "ESPN", 95537, 42, exp = future)
    params <- shiny::parseQueryString(q)
    expect_equal(params$platform, "ESPN")
    expect_equal(params$competitor_id, "42")
    expect_true(verify_handoff_token(
      params$sig,
      params$customer_id,
      params$platform,
      params$league_id,
      params$competitor_id,
      params$exp,
      now = now
    ))
  })
})

test_that("signing without a secret errors", {
  old <- Sys.getenv("NBA_HANDOFF_SECRET", unset = NA)
  Sys.unsetenv("NBA_HANDOFF_SECRET")
  on.exit(if (!is.na(old)) Sys.setenv(NBA_HANDOFF_SECRET = old), add = TRUE)
  expect_error(sign_handoff_token("c", "ESPN", 1, 2, exp = future))
})
