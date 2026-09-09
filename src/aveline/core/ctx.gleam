//// The capability context — every IO operation a handler may perform,
//// grouped by domain and injected by Elixir (closures over Ecto/PubSub).
//// Handlers receive a Ctx and are otherwise pure; tests build a Ctx of
//// stubs (see test/aveline/fakes.gleam).
////
//// Conventions:
////   * Each domain's caps live in src/aveline/caps/<domain>.gleam and
////     are built for real in lib/aveline/gleam/caps/<domain>.ex — those
////     two files must agree on constructor tag + field order, and are
////     owned together.
////   * Caps are fine-grained (one query/statement each), take and return
////     domain types from src/aveline/*, never Ecto structs or Dynamic.
////   * Caps that can't fail in a way handlers should branch on return
////     plain values; genuine DB failures raise on the Elixir side and
////     surface as 500s, same as before the port.
////   * This record and its field order are STABLE shared surface — do
////     not reorder or rename fields while porting a domain; only add to
////     your own caps module.

import aveline/caps/comments.{type CommentsCaps}
import aveline/caps/data_sources.{type DataSourcesCaps}
import aveline/caps/docs.{type DocsCaps}
import aveline/caps/events.{type EventsCaps}
import aveline/caps/keys.{type KeysCaps}
import aveline/caps/kudos.{type KudosCaps}
import aveline/caps/milestones.{type MilestonesCaps}
import aveline/caps/queries.{type QueriesCaps}
import aveline/caps/tags.{type TagsCaps}
import aveline/caps/team.{type TeamCaps}
import aveline/caps/views.{type ViewsCaps}
import aveline/caps/workspaces.{type WorkspacesCaps}

pub type Ctx {
  Ctx(
    comments: CommentsCaps,
    data_sources: DataSourcesCaps,
    docs: DocsCaps,
    events: EventsCaps,
    keys: KeysCaps,
    kudos: KudosCaps,
    milestones: MilestonesCaps,
    queries: QueriesCaps,
    tags: TagsCaps,
    team: TeamCaps,
    views: ViewsCaps,
    workspaces: WorkspacesCaps,
  )
}
