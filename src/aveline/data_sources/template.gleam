//// Connection-template validation — pure port of the private
//// `validate_template/1` in Aveline.DataSources. The template must carry
//// the literal `<password>` placeholder exactly once and a supported
//// scheme + host; on success the derived adapter is returned.
////
//// Scheme/host extraction is a small hand-rolled parser mirroring the
//// distinctions Elixir's URI.parse made for realistic inputs (scheme
//// charset, `//` authority, userinfo/port stripping).

import gleam/list
import gleam/string

pub const placeholder = "<password>"

pub fn validate(template: String) -> Result(String, String) {
  let placeholder_count = list.length(string.split(template, placeholder)) - 1

  case placeholder_count == 1 {
    False ->
      Error(
        "template must contain the literal "
        <> placeholder
        <> " placeholder exactly once (the real password is passed separately and stored encrypted)",
      )
    True -> check_scheme_host(template)
  }
}

fn check_scheme_host(template: String) -> Result(String, String) {
  case parse_scheme(template) {
    Error(Nil) ->
      Error("template must include a scheme: postgres://... or mysql://...")
    Ok(#(scheme, rest)) -> {
      let has_host = has_host(rest)
      case scheme, has_host {
        "postgres", True -> Ok("postgres")
        "postgresql", True -> Ok("postgres")
        "mysql", True -> Ok("mysql")
        "redshift", True -> Ok("redshift")
        s, False if s == "postgres" || s == "postgresql" || s == "mysql" ->
          Error("template must include a host")
        s, _ ->
          Error(
            "unsupported scheme \""
            <> s
            <> "\"; expected postgres://, mysql://, or redshift://",
          )
      }
    }
  }
}

/// The scheme before the first ":" if it looks like one (letter first,
/// then letters/digits/+/-/.), lowercased, plus the remainder.
fn parse_scheme(template: String) -> Result(#(String, String), Nil) {
  case string.split_once(template, ":") {
    Error(Nil) -> Error(Nil)
    Ok(#(before, rest)) ->
      case valid_scheme(before) {
        True -> Ok(#(string.lowercase(before), rest))
        False -> Error(Nil)
      }
  }
}

fn valid_scheme(candidate: String) -> Bool {
  case string.to_graphemes(candidate) {
    [] -> False
    [first, ..rest] ->
      is_alpha(first)
      && list.all(rest, fn(g) {
        is_alpha(g) || is_digit(g) || g == "+" || g == "-" || g == "."
      })
  }
}

fn is_alpha(g: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", g)
}

fn is_digit(g: String) -> Bool {
  string.contains("0123456789", g)
}

/// True when the part after "scheme:" starts with an authority (`//…`)
/// that contains a non-empty host once userinfo and port are stripped.
fn has_host(rest: String) -> Bool {
  case rest {
    "//" <> after -> {
      let authority =
        after
        |> take_until("/")
        |> take_until("?")
        |> take_until("#")
      let host_port = case string.split(authority, "@") |> list.last {
        Ok(part) -> part
        Error(Nil) -> authority
      }
      take_until(host_port, ":") != ""
    }
    _ -> False
  }
}

fn take_until(text: String, stop: String) -> String {
  case string.split_once(text, stop) {
    Ok(#(before, _)) -> before
    Error(Nil) -> text
  }
}
