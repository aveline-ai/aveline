import aveline/docs/doc_listing.{
  Kudos, ManyValues, NoValue, OneValue, Recent, Relevance, Views,
}
import gleam/option.{None, Some}

pub fn parse_sort_defaults_test() {
  assert doc_listing.parse_sort(None) == Ok(None)
  assert doc_listing.parse_sort(Some("")) == Ok(None)
}

pub fn parse_sort_valid_test() {
  assert doc_listing.parse_sort(Some("recent")) == Ok(Some(Recent))
  assert doc_listing.parse_sort(Some("kudos")) == Ok(Some(Kudos))
  assert doc_listing.parse_sort(Some("views")) == Ok(Some(Views))
  assert doc_listing.parse_sort(Some("relevance")) == Ok(Some(Relevance))
}

pub fn parse_sort_invalid_test() {
  assert doc_listing.parse_sort(Some("newest"))
    == Error("sort must be recent | kudos | views | relevance, got: \"newest\"")
}

pub fn parse_limit_test() {
  assert doc_listing.parse_limit(None) == Ok(25)
  assert doc_listing.parse_limit(Some("")) == Ok(25)
  assert doc_listing.parse_limit(Some("100")) == Ok(100)
  assert doc_listing.parse_limit(Some("1")) == Ok(1)
  assert doc_listing.parse_limit(Some("0"))
    == Error("limit must be an integer between 1 and 100")
  assert doc_listing.parse_limit(Some("101"))
    == Error("limit must be an integer between 1 and 100")
  assert doc_listing.parse_limit(Some("nope"))
    == Error("limit must be an integer between 1 and 100")
}

pub fn parse_offset_test() {
  assert doc_listing.parse_offset(None) == Ok(0)
  assert doc_listing.parse_offset(Some("")) == Ok(0)
  assert doc_listing.parse_offset(Some("40")) == Ok(40)
  assert doc_listing.parse_offset(Some("-1"))
    == Error("offset must be a non-negative integer")
  assert doc_listing.parse_offset(Some("x"))
    == Error("offset must be a non-negative integer")
}

pub fn parse_list_param_test() {
  assert doc_listing.parse_list_param(NoValue) == []
  assert doc_listing.parse_list_param(OneValue("")) == []
  assert doc_listing.parse_list_param(OneValue("a,b,,a")) == ["a", "b"]
  assert doc_listing.parse_list_param(ManyValues(["a", "b", "a"])) == ["a", "b"]
}

pub fn resolve_usernames_test() {
  let members = [#("arie", "u1"), #("bo", "u2")]

  assert doc_listing.resolve_usernames(["bo", "arie"], members)
    == Ok(["u2", "u1"])

  assert doc_listing.resolve_usernames(["bo", "who", "nope"], members)
    == Error(["who", "nope"])
}
