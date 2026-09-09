//// /api/keys — list, mint, revoke your own keys. Ports KeyController +
//// Tokens.revoke_guarded's decision logic. The plaintext appears exactly
//// once (mint response); revoking the last active key is refused so an
//// account is never stranded keyless. Not workspace-scoped.

import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/scope.{type Actor}
import aveline/keys/api_key.{type ApiKey, type MintedKey}
import gleam/option.{None, Some}
import gleam/string

pub fn index(ctx: Ctx, actor: Actor) -> List(ApiKey) {
  ctx.keys.list_active(actor.id)
}

pub fn create(
  ctx: Ctx,
  actor: Actor,
  name_param: String,
) -> Result(MintedKey, ApiError) {
  case string.trim(name_param) {
    "" ->
      Error(Invalid(
        "validation_failed",
        "name is required — e.g. \"laptop\" or \"ci\"",
      ))
    name -> Ok(ctx.keys.mint(actor.id, name))
  }
}

pub fn delete(ctx: Ctx, actor: Actor, id: String) -> Result(String, ApiError) {
  case ctx.keys.find_active(actor.id, id) {
    None -> Error(NotFound)
    Some(_) ->
      case ctx.keys.count_other_active(actor.id, id) {
        0 ->
          Error(Invalid(
            "last_key",
            "That's the only active key on this account. Create a replacement first, then revoke this one.",
          ))
        _ -> {
          ctx.keys.revoke(id)
          Ok(id)
        }
      }
  }
}
