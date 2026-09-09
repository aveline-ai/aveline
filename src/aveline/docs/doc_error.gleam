//// Doc-domain handler errors. A superset of ApiError: the extra
//// constructors map (via GleamAdapter.doc_error/1) onto FallbackController
//// tuples that carry structured details, so the fallback stays the single
//// owner of those messages. Passthrough carries a raw Elixir error term
//// from a coarse write cap (changesets, disposition tuples, …) untouched.

import aveline/core/error.{type ApiError, Invalid}
import gleam/dynamic.{type Dynamic}
import gleam/result

pub type DocError {
  Api(ApiError)
  OrientationUndeletable
  PinLimitReached
  PinSlotTaken(slot: Int, occupant: String)
  NotUserDeleted
  UnknownAuthors(usernames: List(String))
  /// Share target username doesn't resolve to a user at all.
  NotMember
  /// Raw Elixir error term returned to the FallbackController unchanged.
  Passthrough(reason: Dynamic)
}

/// Lift a plain ApiError result into a DocError result.
pub fn api(result: Result(a, ApiError)) -> Result(a, DocError) {
  result.map_error(result, Api)
}

/// A generic 422 (`Invalid`) wrapped as a DocError.
pub fn invalid(code: String, message: String) -> DocError {
  Api(Invalid(code, message))
}
