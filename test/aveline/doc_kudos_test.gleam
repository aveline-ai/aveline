import aveline/caps/kudos.{KudosCaps}
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/docs/doc_meta.{DocMeta, Private}
import aveline/docs_fixtures
import aveline/fakes
import aveline/handlers/doc_kudos.{KudosResponse}
import gleam/option.{None, Some}

pub fn missing_doc_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(None))

  assert doc_kudos.toggle(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn own_doc_rejects_self_kudos_test() {
  let doc = docs_fixtures.doc(owner: "user-1")
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_kudos.toggle(ctx, fakes.scope(), "notes")
    == Error(Invalid("self_kudos", "You can't give kudos to your own doc."))
}

pub fn first_kudos_gives_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: docs_fixtures.docs_returning(Some(doc)),
      kudos: KudosCaps(
        find: fn(_, _) { None },
        give: fn(_, _, _) { Nil },
        revoke: fn(_) { panic as "revoke must not run on first kudos" },
        count_for_base: fn(_) { 1 },
      ),
    )

  assert doc_kudos.toggle(ctx, fakes.scope(), "notes")
    == Ok(KudosResponse(given_by_me: True, count: 1))
}

pub fn second_kudos_revokes_test() {
  let doc = docs_fixtures.doc(owner: "user-2")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      docs: docs_fixtures.docs_returning(Some(doc)),
      kudos: KudosCaps(
        find: fn(_, _) { Some("mark-1") },
        give: fn(_, _, _) { panic as "give must not run on toggle-off" },
        revoke: fn(_) { Nil },
        count_for_base: fn(_) { 0 },
      ),
    )

  assert doc_kudos.toggle(ctx, fakes.scope(), "notes")
    == Ok(KudosResponse(given_by_me: False, count: 0))
}

pub fn private_doc_hidden_from_non_shared_member_test() {
  let doc = DocMeta(..docs_fixtures.doc(owner: "user-2"), visibility: Private)
  let ctx = Ctx(..fakes.ctx(), docs: docs_fixtures.docs_returning(Some(doc)))

  assert doc_kudos.toggle(ctx, fakes.scope(), "notes") == Error(NotFound)
}
