//// Keys IO capabilities (API-token self-service + the /me identity
//// read). Built for real in lib/aveline/gleam/caps/keys.ex; keep the
//// two in lockstep (tag + field order).

import aveline/accounts/user_info.{type UserInfo}
import aveline/keys/api_key.{type ApiKey, type MintedKey}
import gleam/option.{type Option}

pub type KeysCaps {
  KeysCaps(
    /// Full user record for an actor id (email/display_name for /me).
    get_user: fn(String) -> UserInfo,
    /// Active (non-revoked) keys for a user, newest first.
    list_active: fn(String) -> List(ApiKey),
    /// Mint a token: (user_id, name). Plaintext appears here exactly once.
    mint: fn(String, String) -> MintedKey,
    /// Active key id for (user_id, token_id) if the user owns it.
    find_active: fn(String, String) -> Option(String),
    /// Count of the user's OTHER active keys: (user_id, token_id).
    count_other_active: fn(String, String) -> Int,
    /// Mark a key revoked by id.
    revoke: fn(String) -> Nil,
  )
}

pub fn stub() -> KeysCaps {
  KeysCaps(
    get_user: fn(_) { panic as "stub keys.get_user" },
    list_active: fn(_) { panic as "stub keys.list_active" },
    mint: fn(_, _) { panic as "stub keys.mint" },
    find_active: fn(_, _) { panic as "stub keys.find_active" },
    count_other_active: fn(_, _) { panic as "stub keys.count_other_active" },
    revoke: fn(_) { panic as "stub keys.revoke" },
  )
}
