//// Fake Ctx for handler tests. Every cap starts as its domain's stub
//// (panics on use, so untouched IO can't sneak into a handler); tests
//// override just the caps in play via record-update syntax:
////
////   let ctx = Ctx(..fakes.ctx(), kudos: KudosCaps(..))
////
//// This file is STABLE shared surface — put domain-specific fixture
//// helpers in your own test/aveline/<domain>_fixtures.gleam, not here.

import aveline/caps/comments
import aveline/caps/data_sources
import aveline/caps/docs
import aveline/caps/events
import aveline/caps/keys
import aveline/caps/kudos
import aveline/caps/milestones
import aveline/caps/queries
import aveline/caps/tags
import aveline/caps/team
import aveline/caps/views
import aveline/caps/workspaces
import aveline/core/ctx.{type Ctx, Ctx}
import aveline/core/scope.{Actor, Scope, Workspace}

pub fn ctx() -> Ctx {
  Ctx(
    comments: comments.stub(),
    data_sources: data_sources.stub(),
    docs: docs.stub(),
    events: events.stub(),
    keys: keys.stub(),
    kudos: kudos.stub(),
    milestones: milestones.stub(),
    queries: queries.stub(),
    tags: tags.stub(),
    team: team.stub(),
    views: views.stub(),
    workspaces: workspaces.stub(),
  )
}

pub fn scope() -> scope.Scope {
  Scope(
    workspace: Workspace(id: "ws-1", slug: "acme"),
    actor: Actor(id: "user-1", username: "arie"),
  )
}
