//// Handler errors. The Elixir adapter maps these onto the legacy
//// FallbackController tuples, which stays the single owner of HTTP
//// status codes and the error-code catalog agents branch on.

pub type ApiError {
  /// Inaccessible and nonexistent are indistinguishable on purpose:
  /// existence is information.
  NotFound
  Forbidden(message: String)
  /// Generic 422 with a machine-readable code (e.g. "self_kudos").
  Invalid(code: String, message: String)
}
