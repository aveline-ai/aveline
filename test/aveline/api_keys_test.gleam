import aveline/caps/keys.{KeysCaps} as keys_caps
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/fakes
import aveline/handlers/api_keys
import aveline/keys/api_key.{type ApiKey, ApiKey, MintedKey}
import gleam/option.{None, Some}

fn actor() {
  fakes.scope().actor
}

fn key(id: String, name: String) -> ApiKey {
  ApiKey(
    id: id,
    name: name,
    masked: "avl_…abcd",
    created_at: "2026-09-01T00:00:00Z",
    last_used_at: None,
  )
}

pub fn index_lists_the_actors_active_keys_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(..keys_caps.stub(), list_active: fn(user_id) {
        assert user_id == "user-1"
        [key("k1", "laptop"), key("k2", "ci")]
      }),
    )

  assert api_keys.index(ctx, actor()) == [key("k1", "laptop"), key("k2", "ci")]
}

pub fn create_requires_a_name_test() {
  let expected =
    Error(Invalid(
      "validation_failed",
      "name is required — e.g. \"laptop\" or \"ci\"",
    ))

  assert api_keys.create(fakes.ctx(), actor(), "") == expected
  assert api_keys.create(fakes.ctx(), actor(), "   ") == expected
}

pub fn create_trims_and_mints_test() {
  let minted = MintedKey(key: key("k9", "laptop"), plaintext: "avl_secret")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(..keys_caps.stub(), mint: fn(user_id, name) {
        assert user_id == "user-1"
        assert name == "laptop"
        minted
      }),
    )

  assert api_keys.create(ctx, actor(), "  laptop  ") == Ok(minted)
}

pub fn delete_unknown_or_foreign_key_is_not_found_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(..keys_caps.stub(), find_active: fn(_, _) { None }),
    )

  assert api_keys.delete(ctx, actor(), "k1") == Error(NotFound)
}

pub fn delete_refuses_the_last_active_key_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(
        ..keys_caps.stub(),
        find_active: fn(_, _) { Some("k1") },
        count_other_active: fn(_, _) { 0 },
      ),
    )

  assert api_keys.delete(ctx, actor(), "k1")
    == Error(Invalid(
      "last_key",
      "That's the only active key on this account. Create a replacement first, then revoke this one.",
    ))
}

pub fn delete_revokes_when_a_spare_remains_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(
        ..keys_caps.stub(),
        find_active: fn(user_id, id) {
          assert user_id == "user-1"
          assert id == "k1"
          Some("k1")
        },
        count_other_active: fn(_, _) { 1 },
        revoke: fn(id) {
          assert id == "k1"
          Nil
        },
      ),
    )

  assert api_keys.delete(ctx, actor(), "k1") == Ok("k1")
}
