//// API-key display shapes. `masked` is computed Elixir-side
//// (Aveline.Tokens.masked/1); no hash or plaintext ever crosses here —
//// except the mint response's one-time plaintext, which the API returns
//// to the caller exactly once by design.

import gleam/option.{type Option}

pub type ApiKey {
  ApiKey(
    id: String,
    name: String,
    masked: String,
    created_at: String,
    last_used_at: Option(String),
  )
}

pub type MintedKey {
  MintedKey(key: ApiKey, plaintext: String)
}
