import aveline/caps/data_sources.{DataSourcesCaps, DsNameTaken, DsRejected} as ds_caps
import aveline/core/ctx.{Ctx}
import aveline/core/error.{Invalid, NotFound}
import aveline/data_sources/data_source_info.{DataSourceInfo}
import aveline/data_sources_fixtures as fixtures
import aveline/fakes
import aveline/handlers/data_sources.{CreateRequest, UpdateRequest} as handler
import gleam/option.{None, Some}

fn validation_failed() {
  Error(Invalid("validation_failed", "Validation failed."))
}

fn valid_url() {
  "postgres://u:<password>@h/db"
}

pub fn index_lists_sources_test() {
  let sources = [fixtures.source(name: "prod", adapter: "postgres")]
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        list_for_workspace: fn(ws_id) {
          assert ws_id == "ws-1"
          sources
        },
      ),
    )

  assert handler.index(ctx, fakes.scope()) == sources
}

// ===== create =====

pub fn create_reserved_names_are_refused_test() {
  let req =
    CreateRequest(name: " Derived ", url: Some(valid_url()), password: None)

  assert handler.create(fakes.ctx(), fakes.scope(), req)
    == Error(Invalid(
      "reserved_name",
      "\"derived\" is reserved for the built-in catalog source — pick another",
    ))
}

pub fn create_requires_a_password_test() {
  let req = CreateRequest(name: "prod", url: Some(valid_url()), password: None)

  assert handler.create(fakes.ctx(), fakes.scope(), req)
    == Error(Invalid(
      "invalid_data_source_url",
      "password is required (pass \"\" for passwordless databases)",
    ))
}

pub fn create_requires_a_string_template_test() {
  let req =
    CreateRequest(name: "prod", url: None, password: Some(fixtures.secret("x")))

  assert handler.create(fakes.ctx(), fakes.scope(), req)
    == Error(Invalid("invalid_data_source_url", "template must be a string"))
}

pub fn create_rejects_a_bad_template_test() {
  let req =
    CreateRequest(
      name: "prod",
      url: Some("http://u:<password>@h/db"),
      password: Some(fixtures.secret("x")),
    )

  assert handler.create(fakes.ctx(), fakes.scope(), req)
    == Error(Invalid(
      "invalid_data_source_url",
      "unsupported scheme \"http\"; expected postgres://, mysql://, or redshift://",
    ))
}

pub fn create_rejects_a_non_slug_name_test() {
  let req =
    CreateRequest(
      name: "has space",
      url: Some(valid_url()),
      password: Some(fixtures.secret("x")),
    )

  assert handler.create(fakes.ctx(), fakes.scope(), req) == validation_failed()
}

pub fn create_normalizes_name_and_calls_the_cap_test() {
  let created = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        create: fn(ws_id, name, template, _password, user_id) {
          assert ws_id == "ws-1"
          assert name == "prod"
          assert template == valid_url()
          assert user_id == "user-1"
          Ok(created)
        },
      ),
    )
  let req =
    CreateRequest(
      name: "  PROD ",
      url: Some(valid_url()),
      password: Some(fixtures.secret("hunter2")),
    )

  assert handler.create(ctx, fakes.scope(), req) == Ok(created)
}

pub fn create_maps_name_conflicts_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(..ds_caps.stub(), create: fn(_, _, _, _, _) {
        Error(DsNameTaken)
      }),
    )
  let req =
    CreateRequest(
      name: "prod",
      url: Some(valid_url()),
      password: Some(fixtures.secret("x")),
    )

  assert handler.create(ctx, fakes.scope(), req) == validation_failed()
}

pub fn create_echoes_context_refusals_test() {
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(..ds_caps.stub(), create: fn(_, _, _, _, _) {
        Error(DsRejected("invalid_data_source_url", "boom"))
      }),
    )
  let req =
    CreateRequest(
      name: "prod",
      url: Some(valid_url()),
      password: Some(fixtures.secret("x")),
    )

  assert handler.create(ctx, fakes.scope(), req)
    == Error(Invalid("invalid_data_source_url", "boom"))
}

// ===== update =====

pub fn update_missing_source_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(None))
  let req = UpdateRequest(new_name: None, url: None, password: None)

  assert handler.update(ctx, fakes.scope(), "nope", req) == Error(NotFound)
}

pub fn update_workspace_source_is_immutable_test() {
  let builtin = fixtures.source(name: "derived", adapter: "workspace")
  let ctx =
    Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(Some(builtin)))
  let req = UpdateRequest(new_name: Some("other"), url: None, password: None)

  assert handler.update(ctx, fakes.scope(), "derived", req)
    == Error(Invalid(
      "workspace_source_immutable",
      "the workspace source is built in — it can't be renamed or repointed",
    ))
}

pub fn update_template_change_requires_the_password_test() {
  let current = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(Some(current)))
  let req =
    UpdateRequest(
      new_name: None,
      url: Some("postgres://u:<password>@evil.example.com/db"),
      password: None,
    )

  assert handler.update(ctx, fakes.scope(), "prod", req)
    == Error(Invalid(
      "password_required",
      "changing the connection template requires supplying the password with it — a stored secret is never combined with connection settings it wasn't written with",
    ))
}

pub fn update_rejects_a_bad_new_name_test() {
  let current = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(Some(current)))
  let req = UpdateRequest(new_name: Some("Bad Name"), url: None, password: None)

  assert handler.update(ctx, fakes.scope(), "prod", req) == validation_failed()
}

pub fn update_rename_alone_keeps_template_and_secret_test() {
  let current = fixtures.source(name: "prod", adapter: "postgres")
  let renamed = fixtures.source(name: "analytics", adapter: "postgres")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(current) },
        edit: fn(id, name, template, password, user_id) {
          assert id == "ds-1"
          assert name == "analytics"
          assert template == current.url
          assert password == None
          assert user_id == "user-1"
          Ok(renamed)
        },
      ),
    )
  let req =
    UpdateRequest(new_name: Some(" Analytics "), url: None, password: None)

  assert handler.update(ctx, fakes.scope(), "prod", req) == Ok(renamed)
}

pub fn update_template_with_password_goes_through_test() {
  let current = fixtures.source(name: "prod", adapter: "postgres")
  let next_url = "mysql://u:<password>@h2/db"
  let edited =
    DataSourceInfo(
      ..current,
      adapter: "mysql",
      url: next_url,
      version_number: 2,
    )
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(current) },
        edit: fn(_, name, template, password, _) {
          assert name == "prod"
          assert template == next_url
          assert password != None
          Ok(edited)
        },
      ),
    )
  let req =
    UpdateRequest(
      new_name: None,
      url: Some(next_url),
      password: Some(fixtures.secret("fresh")),
    )

  assert handler.update(ctx, fakes.scope(), "prod", req) == Ok(edited)
}

pub fn update_echoes_context_refusals_test() {
  let current = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(current) },
        edit: fn(_, _, _, _, _) { Error(DsNameTaken) },
      ),
    )
  let req = UpdateRequest(new_name: Some("taken"), url: None, password: None)

  assert handler.update(ctx, fakes.scope(), "prod", req) == validation_failed()
}

// ===== query =====

pub fn query_requires_sql_test() {
  let expected = Error(Invalid("validation_failed", "query is required"))

  assert handler.query(fakes.ctx(), fakes.scope(), "prod", None) == expected
  assert handler.query(fakes.ctx(), fakes.scope(), "prod", Some("   "))
    == expected
}

pub fn query_missing_source_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(None))

  assert handler.query(ctx, fakes.scope(), "nope", Some("select 1"))
    == Error(NotFound)
}

pub fn query_workspace_source_rides_the_catalog_test() {
  let builtin = fixtures.source(name: "derived", adapter: "workspace")
  let rows = fixtures.query_result("rows")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(builtin) },
        run_catalog_query: fn(ws_id, sql) {
          assert ws_id == "ws-1"
          assert sql == "select 1"
          Ok(rows)
        },
      ),
    )

  assert handler.query(ctx, fakes.scope(), "derived", Some("select 1"))
    == Ok(rows)
}

pub fn query_external_source_uses_the_runner_test() {
  let source = fixtures.source(name: "prod", adapter: "postgres")
  let rows = fixtures.query_result("rows")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(source) },
        run_source_query: fn(id, sql) {
          assert id == "ds-1"
          assert sql == "select 1"
          Ok(rows)
        },
      ),
    )

  assert handler.query(ctx, fakes.scope(), "prod", Some("select 1")) == Ok(rows)
}

pub fn query_failures_map_to_query_failed_test() {
  let source = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(source) },
        run_source_query: fn(_, _) { Error("connection failed") },
      ),
    )

  assert handler.query(ctx, fakes.scope(), "prod", Some("select 1"))
    == Error(Invalid("query_failed", "connection failed"))
}

// ===== delete =====

pub fn delete_missing_source_is_not_found_test() {
  let ctx = Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(None))

  assert handler.delete(ctx, fakes.scope(), "nope") == Error(NotFound)
}

pub fn delete_workspace_source_is_immutable_test() {
  let builtin = fixtures.source(name: "derived", adapter: "workspace")
  let ctx =
    Ctx(..fakes.ctx(), data_sources: fixtures.sources_returning(Some(builtin)))

  assert handler.delete(ctx, fakes.scope(), "derived")
    == Error(Invalid(
      "workspace_source_immutable",
      "the workspace source is built in — it can't be deleted",
    ))
}

pub fn delete_soft_deletes_test() {
  let source = fixtures.source(name: "prod", adapter: "postgres")
  let ctx =
    Ctx(
      ..fakes.ctx(),
      data_sources: DataSourcesCaps(
        ..ds_caps.stub(),
        get_current_by_name: fn(_, _) { Some(source) },
        soft_delete: fn(id, user_id) {
          assert id == "ds-1"
          assert user_id == "user-1"
          Nil
        },
      ),
    )

  assert handler.delete(ctx, fakes.scope(), "prod") == Ok(Nil)
}
