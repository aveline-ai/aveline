//// Milestone input rules, pure. Ports Milestone.changeset: trim name
//// and description, name required (1..80 graphemes), date required and
//// a real ISO8601 calendar date. Every failure maps to the same 422
//// "validation_failed" envelope the changeset produced before the port.

import aveline/core/error.{type ApiError, Invalid}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

fn failed() -> ApiError {
  Invalid("validation_failed", "Validation failed.")
}

pub fn name(raw: String) -> Result(String, ApiError) {
  let trimmed = string.trim(raw)
  let length = string.length(trimmed)
  case length >= 1 && length <= 80 {
    True -> Ok(trimmed)
    False -> Error(failed())
  }
}

pub fn date(raw: Option(String)) -> Result(String, ApiError) {
  case raw {
    Some(s) ->
      case valid_iso_date(s) {
        True -> Ok(s)
        False -> Error(failed())
      }
    None -> Error(failed())
  }
}

/// Trim; a blank description is no description (mirrors the changeset).
pub fn description(raw: Option(String)) -> Option(String) {
  case raw {
    None -> None
    Some(s) ->
      case string.trim(s) {
        "" -> None
        trimmed -> Some(trimmed)
      }
  }
}

/// Strict YYYY-MM-DD with real calendar rules (leap years included) —
/// the strings Elixir's Date.from_iso8601 accepts for four-digit years.
fn valid_iso_date(s: String) -> Bool {
  case string.split(s, "-") {
    [y, m, d] ->
      case digits(y, 4), digits(m, 2), digits(d, 2) {
        Ok(year), Ok(month), Ok(day) ->
          month >= 1
          && month <= 12
          && day >= 1
          && day <= days_in_month(year, month)
        _, _, _ -> False
      }
    _ -> False
  }
}

fn digits(s: String, expected_length: Int) -> Result(Int, Nil) {
  let chars = string.to_graphemes(s)
  case
    list.length(chars) == expected_length
    && list.all(chars, string.contains("0123456789", _))
  {
    True -> int.parse(s)
    False -> Error(Nil)
  }
}

fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    2 ->
      case leap_year(year) {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
}

fn leap_year(year: Int) -> Bool {
  year % 4 == 0 && { year % 100 != 0 || year % 400 == 0 }
}
