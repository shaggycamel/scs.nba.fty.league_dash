#' Map game-table column labels back to real dates
#'
#' @description
#' The wide game tables name their columns after `fmt_date`, built as
#' `format(game_date, "%a (%d/%m)")`, which carries no year. A label therefore
#' cannot be parsed back on its own: `parse_date_time("Mon (04/01)", orders =
#' "%a (%d/%m)")` fills in the *current* year, which is wrong for any matchup
#' week straddling New Year.
#'
#' Recovers the year instead by anchoring the label to a reference date - the
#' matchup start, since every date column falls on or after it. The columns
#' cannot simply be walked off that start one day at a time: they are the days
#' that have games, so they skip the All-Star break, and a matchup whose first
#' day has no games has no column for it.
#'
#' @return A Date vector named by column label, in column order.
#'
#' @noRd
col_dates_from_labels <- function(col_names, ref_date) {
  date_cols <- str_subset(col_names, "/")
  dm <- str_match(date_cols, "\\((\\d{2})/(\\d{2})\\)")
  ref_year <- as.integer(format(ref_date, "%Y"))

  dts <- as.Date(sprintf("%04d-%s-%s", ref_year, dm[, 3], dm[, 2]))

  # A label falling earlier in the calendar than the matchup start belongs to the
  # next year - a week running from December into January. The NA case is 29
  # February landing on a non-leap year.
  roll <- is.na(dts) | dts < ref_date
  dts[roll] <- as.Date(sprintf("%04d-%s-%s", ref_year + 1L, dm[roll, 3], dm[roll, 2]))

  set_names(dts, date_cols)
}

#' Give every day of the matchup a column
#'
#' @description
#' Columns exist only for days that have games, so a week containing a day off
#' (Thanksgiving, Christmas, the All-Star break) reads shorter than its
#' neighbours and the weekdays stop lining up between matchups. Add a filled
#' column for each missing day and put the date columns back in date order.
#'
#' The tables carry the two days after the matchup too - `matchup_end_plus` in
#' data_h2h.R - so the range runs to `matchup_end + post_matchup_days`, letting a
#' post-matchup day with no games have a column as well. That extension only
#' applies when `matchup_end` is within reach of the columns already there: Post
#' Fantasy's sits in 2999, and filling to it would lay out nine centuries of
#' columns. The range is therefore always bounded by real data.
#'
#' @noRd
fill_missing_days <- function(df, matchup_start, matchup_end = NULL, fill = 0, post_matchup_days = 2) {
  dts <- col_dates_from_labels(names(df), matchup_start)
  if (length(dts) == 0) {
    return(df)
  }

  last_day <- max(dts)
  if (!is.null(matchup_end) && !is.na(matchup_end) && matchup_end <= last_day + post_matchup_days) {
    last_day <- max(last_day, matchup_end + post_matchup_days)
  }

  every_day <- seq(min(matchup_start, min(dts)), last_day, by = "day")
  missing <- setdiff(format(every_day, "%a (%d/%m)"), names(dts))
  if (length(missing) > 0) {
    # Match the columns already there, so a filled table's totals keep the type
    # they had - the schedule counts are integer, the h2h cells character.
    filler <- rep(fill, nrow(df))
    storage.mode(filler) <- storage.mode(df[[names(dts)[1]]])
    df[missing] <- filler
  }

  # Anything that is not a date column keeps its leading position.
  dts <- col_dates_from_labels(names(df), matchup_start)
  df[c(setdiff(names(df), names(dts)), names(sort(dts)))]
}

#' Columns covered by the schedule table's Pin total
#'
#' @description
#' Looking forward, the pinned day through to the matchup end; looking back, the
#' matchup start up to the day before the pin. Both are bounded by the matchup
#' itself, so the two post-matchup columns never count towards the total.
#'
#' Selecting by date rather than by column position matters because the columns
#' are the days that have games: a matchup whose first day is empty has no column
#' for it, and days off mid-matchup (Thanksgiving, Christmas, the All-Star break)
#' leave gaps that shift every later column.
#'
#' @noRd
pin_columns <- function(col_dates, pin_date, matchup_start, matchup_end, pin_dir) {
  if (pin_dir == "+") {
    names(col_dates)[col_dates >= pin_date & col_dates <= matchup_end]
  } else {
    names(col_dates)[col_dates >= matchup_start & col_dates < pin_date]
  }
}


#' game_tbl_col_fmt
#'
#' @description A fct function
#'
#' @return The return value, if any, from executing the function.
#'
#' @noRd
#'
game_tbl_col_fmt <- function(df, dt, mup_end, col_dates, type = "player", starter_count = 10) {
  col_fmt <- map(set_names(str_subset(colnames(df), "\\/")), \(x) {
    nm <- str_split_1(x, " ")
    col_date <- col_dates[[x]]
    colDef(
      minWidth = 70,
      align = "center",
      header = tags$span(nm[1], tags$br(), nm[2]),
      style = function(value, index) {
        if (
          type == "player" &&
            (col_date < coalesce(df$min_grey_date[index], as.Date("1000-01-01")) |
              col_date > coalesce(df$max_grey_date[index], as.Date("3000-01-01")))
        ) {
          list(background = "#d7d7d5", color = "#d7d7d5")
        } else if (
          str_detect(as.character(value), "\\*") ||
            (type == "sum" && isTRUE(as.numeric(str_remove(value, "\\*")) > starter_count))
        ) {
          list(background = "#ea7878ff")
        } else if (col_date == dt) {
          list(background = "#f1e78e94")
        } else if (col_date > mup_end) {
          list(background = "#eee5ff94")
        }
      }
    )
  })
  col_fmt[["games_remaining"]] <- colDef(
    minWidth = 70,
    align = "center",
    header = tags$span("Games", tags$br(), "Remaining"),
    style = list(background = "#96e5cbeb")
  )
  col_fmt[["min_grey_date"]] <- colDef(show = FALSE)
  col_fmt[["max_grey_date"]] <- colDef(show = FALSE)
  col_fmt[["competitor"]] <- colDef(show = FALSE)
  col_fmt[["player_id"]] <- colDef(show = FALSE)
  col_fmt[["player_name"]] <- colDef(
    show = ifelse(type == "sum", FALSE, TRUE),
    name = "",
    align = "left",
    minWidth = 115,
    sticky = "left",
    style = list(
      whiteSpace = "nowrap",
      overflow = "hidden",
      textOverflow = "ellipsis"
    )
  )
  col_fmt[["player_team"]] <- colDef(
    name = "",
    # align = ifelse(type == "sum", "center", "left"),
    minWidth = ifelse(type == "sum", 65 + 115, 65),
    sticky = "left",
    style = list(
      whiteSpace = "nowrap",
      overflow = "hidden",
      textOverflow = "ellipsis"
    )
  )

  col_fmt
}
