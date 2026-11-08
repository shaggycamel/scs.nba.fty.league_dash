# Password hashing -----------------------------------------------------------
# Default scheme is bcrypt ($2a$...), produced by the compiled {bcrypt} package,
# so verification is fast (tens of milliseconds) on constrained hosts. The
# legacy PBKDF2-HMAC-SHA256 scheme is still supported for verifying existing
# hashes; its encoded output is a self-describing string:
#
#   pbkdf2-sha256$<iterations>$<salt_hex>$<hash_hex>
#
# verify_password() also recognises argon2 ($argon2...) hashes when the
# corresponding package is installed, so the column can hold a different scheme
# without a migration.

raw_to_hex <- function(x) {
  paste(sprintf("%02x", as.integer(x)), collapse = "")
}

hex_to_raw <- function(s) {
  if (is.null(s) || length(s) != 1L || is.na(s) || nchar(s) %% 2L != 0L || !grepl("^[0-9a-fA-F]*$", s)) {
    return(NULL)
  }
  if (!nzchar(s)) {
    return(raw(0))
  }
  as.raw(strtoi(substring(s, seq(1L, nchar(s), 2L), seq(2L, nchar(s), 2L)), 16L))
}

i2osp <- function(x, len = 4L) {
  out <- raw(len)
  for (k in len:1L) {
    out[k] <- as.raw(x %% 256L)
    x <- x %/% 256L
  }
  out
}

xor_raw <- function(a, b) {
  as.raw(bitwXor(as.integer(a), as.integer(b)))
}

# PBKDF2-HMAC-SHA256 (RFC 2898). Not exported.
pbkdf2_sha256 <- function(password, salt, iterations, dklen) {
  hlen <- 32L
  blocks <- ceiling(dklen / hlen)
  out <- raw(0)
  for (i in seq_len(blocks)) {
    u <- digest::hmac(password, c(salt, i2osp(i)), algo = "sha256", serialize = FALSE, raw = TRUE)
    t <- u
    if (iterations > 1L) {
      for (j in seq_len(iterations - 1L)) {
        u <- digest::hmac(password, u, algo = "sha256", serialize = FALSE, raw = TRUE)
        t <- xor_raw(t, u)
      }
    }
    out <- c(out, t)
  }
  out[seq_len(dklen)]
}

constant_time_eq <- function(a, b) {
  if (!is.raw(a) || !is.raw(b) || length(a) != length(b) || length(a) == 0L) {
    return(FALSE)
  }
  acc <- 0L
  for (i in seq_along(a)) {
    acc <- bitwOr(acc, bitwXor(as.integer(a[i]), as.integer(b[i])))
  }
  acc == 0L
}

#' Hash a password
#'
#' Produces an encoded hash suitable for storage in a text column
#' (`fty.customer.password_hash`). Defaults to bcrypt (`scheme = "bcrypt"`);
#' pass `scheme = "pbkdf2"` for the legacy PBKDF2-HMAC-SHA256 format.
#'
#' @param password The password (single string).
#' @param cost bcrypt cost (log2 of the key-stretching rounds), 4-31. Defaults
#'   to 12.
#' @param scheme Hashing scheme; `"bcrypt"` (default) or `"pbkdf2"`.
#' @param iterations PBKDF2 iteration count (ignored for bcrypt).
#' @param salt Optional PBKDF2 salt as raw bytes; random by default.
#'
#' @return An encoded hash string.
#' @export
hash_password <- function(
  password,
  cost = 12L,
  scheme = c("bcrypt", "pbkdf2"),
  iterations = 100000L,
  salt = openssl::rand_bytes(16L)
) {
  stopifnot(is.character(password), length(password) == 1L, nzchar(password))
  scheme <- match.arg(scheme)

  if (scheme == "bcrypt") {
    if (!requireNamespace("bcrypt", quietly = TRUE)) {
      stop("the {bcrypt} package is required to hash passwords", call. = FALSE)
    }
    cost <- as.integer(cost)
    if (is.na(cost) || cost < 4L || cost > 31L) {
      stop("cost must be an integer between 4 and 31", call. = FALSE)
    }
    return(bcrypt::hashpw(password, bcrypt::gensalt(cost)))
  }

  iterations <- as.integer(iterations)
  if (is.na(iterations) || iterations < 1L) {
    stop("iterations must be a positive integer", call. = FALSE)
  }

  dk <- pbkdf2_sha256(charToRaw(password), salt, iterations, 32L)
  sprintf("pbkdf2-sha256$%d$%s$%s", iterations, raw_to_hex(salt), raw_to_hex(dk))
}

#' Verify a password against an encoded hash
#'
#' @param password The password to check.
#' @param hash The stored encoded hash.
#'
#' @return `TRUE` when the password matches, otherwise `FALSE`.
#' @export
verify_password <- function(password, hash) {
  if (
    is.null(hash) ||
      length(hash) != 1L ||
      is.na(hash) ||
      !nzchar(hash) ||
      !is.character(password) ||
      length(password) != 1L
  ) {
    return(FALSE)
  }

  if (startsWith(hash, "pbkdf2-sha256$")) {
    parts <- strsplit(hash, "$", fixed = TRUE)[[1]]
    if (length(parts) != 4L) {
      return(FALSE)
    }
    iterations <- suppressWarnings(as.integer(parts[2]))
    salt <- hex_to_raw(parts[3])
    expected <- hex_to_raw(parts[4])
    if (is.na(iterations) || iterations < 1L || is.null(salt) || is.null(expected) || length(expected) == 0L) {
      return(FALSE)
    }
    actual <- pbkdf2_sha256(charToRaw(password), salt, iterations, length(expected))
    return(constant_time_eq(actual, expected))
  }

  if (grepl("^\\$2[aby]\\$", hash)) {
    if (requireNamespace("bcrypt", quietly = TRUE)) {
      return(isTRUE(bcrypt::checkpw(password, hash)))
    }
    return(FALSE)
  }

  if (startsWith(hash, "$argon2")) {
    if (requireNamespace("argon2", quietly = TRUE)) {
      return(tryCatch(isTRUE(argon2::verify_password(hash, password)), error = function(e) FALSE))
    }
    return(FALSE)
  }

  FALSE
}
