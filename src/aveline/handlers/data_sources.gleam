//// /data-sources — list, connect, edit, ad-hoc query, delete. Ports
//// DataSourceController + the decision logic of Aveline.DataSources
//// (reserved names, template/password pairing rules, immutability of
//// the built-in workspace source). Query execution and everything
//// touching the credential stay coarse Elixir caps.

import aveline/caps/data_sources.{
  type QueryResult, type Secret, DsNameTaken, DsRejected,
}
import aveline/core/ctx.{type Ctx}
import aveline/core/error.{type ApiError, Invalid, NotFound}
import aveline/core/scope.{type Scope}
import aveline/data_sources/data_source_info.{type DataSourceInfo}
import aveline/data_sources/template
import aveline/slug
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type CreateRequest {
  CreateRequest(name: String, url: Option(String), password: Option(Secret))
}

pub type UpdateRequest {
  UpdateRequest(
    new_name: Option(String),
    url: Option(String),
    password: Option(Secret),
  )
}

pub fn index(ctx: Ctx, scope: Scope) -> List(DataSourceInfo) {
  ctx.data_sources.list_for_workspace(scope.workspace.id)
}

pub fn create(
  ctx: Ctx,
  scope: Scope,
  req: CreateRequest,
) -> Result(DataSourceInfo, ApiError) {
  let name = req.name |> string.trim |> string.lowercase

  case name == "derived" || name == "workspace" {
    True ->
      Error(Invalid(
        "reserved_name",
        "\""
          <> name
          <> "\" is reserved for the built-in catalog source — pick another",
      ))
    False ->
      case req.password {
        None ->
          Error(Invalid(
            "invalid_data_source_url",
            "password is required (pass \"\" for passwordless databases)",
          ))
        Some(password) -> {
          use url <- result.try(validate_template(req.url))
          case slug.validate(name) {
            False -> Error(validation_failed())
            True ->
              ctx.data_sources.create(
                scope.workspace.id,
                name,
                url,
                password,
                scope.actor.id,
              )
              |> result.map_error(map_write_error)
          }
        }
      }
  }
}

pub fn update(
  ctx: Ctx,
  scope: Scope,
  name: String,
  req: UpdateRequest,
) -> Result(DataSourceInfo, ApiError) {
  case ctx.data_sources.get_current_by_name(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(ds) ->
      case ds.adapter {
        "workspace" ->
          Error(Invalid(
            "workspace_source_immutable",
            "the workspace source is built in — it can't be renamed or repointed",
          ))
        _ -> {
          let templ = option.unwrap(req.url, ds.url)
          let template_changed = templ != ds.url
          case template_changed && option.is_none(req.password) {
            True ->
              Error(Invalid(
                "password_required",
                "changing the connection template requires supplying the password with it — a stored secret is never combined with connection settings it wasn't written with",
              ))
            False -> {
              use _ <- result.try(validate_template(Some(templ)))
              use next_name <- result.try(resolve_name(req.new_name, ds.name))
              ctx.data_sources.edit(
                ds.id,
                next_name,
                templ,
                req.password,
                scope.actor.id,
              )
              |> result.map_error(map_write_error)
            }
          }
        }
      }
  }
}

pub fn query(
  ctx: Ctx,
  scope: Scope,
  name: String,
  query_param: Option(String),
) -> Result(QueryResult, ApiError) {
  case query_param {
    None -> Error(Invalid("validation_failed", "query is required"))
    Some(sql) ->
      case string.trim(sql) {
        "" -> Error(Invalid("validation_failed", "query is required"))
        _ ->
          case ctx.data_sources.get_current_by_name(scope.workspace.id, name) {
            None -> Error(NotFound)
            Some(ds) -> {
              // The built-in "derived" source rides the catalog engine;
              // external sources dial fresh (see controller moduledoc).
              let run = case ds.adapter {
                "workspace" ->
                  ctx.data_sources.run_catalog_query(scope.workspace.id, sql)
                _ -> ctx.data_sources.run_source_query(ds.id, sql)
              }
              result.map_error(run, fn(msg) { Invalid("query_failed", msg) })
            }
          }
      }
  }
}

pub fn delete(ctx: Ctx, scope: Scope, name: String) -> Result(Nil, ApiError) {
  case ctx.data_sources.get_current_by_name(scope.workspace.id, name) {
    None -> Error(NotFound)
    Some(ds) ->
      case ds.adapter {
        "workspace" ->
          Error(Invalid(
            "workspace_source_immutable",
            "the workspace source is built in — it can't be deleted",
          ))
        _ -> {
          ctx.data_sources.soft_delete(ds.id, scope.actor.id)
          Ok(Nil)
        }
      }
  }
}

fn validate_template(url: Option(String)) -> Result(String, ApiError) {
  case url {
    None ->
      Error(Invalid("invalid_data_source_url", "template must be a string"))
    Some(t) ->
      case template.validate(t) {
        Ok(_adapter) -> Ok(t)
        Error(msg) -> Error(Invalid("invalid_data_source_url", msg))
      }
  }
}

/// A rename is normalized (trim + downcase, as the changeset does) and
/// must be a valid slug-style name.
fn resolve_name(
  new_name: Option(String),
  current: String,
) -> Result(String, ApiError) {
  case new_name {
    None -> Ok(current)
    Some(n) -> {
      let n = n |> string.trim |> string.lowercase
      case slug.validate(n) {
        True -> Ok(n)
        False -> Error(validation_failed())
      }
    }
  }
}

fn map_write_error(err: data_sources.DsWriteError) -> ApiError {
  case err {
    DsNameTaken -> validation_failed()
    DsRejected(code, message) -> Invalid(code, message)
  }
}

fn validation_failed() -> ApiError {
  Invalid("validation_failed", "Validation failed.")
}
