//// Activity-feed event attributes (mirrors Aveline.Events.record/1).

import gleam/option.{type Option}

pub type ActorType {
  Human
  Agent
}

pub type EventAttrs {
  EventAttrs(
    workspace_id: String,
    actor: String,
    actor_type: ActorType,
    action: String,
    target_kind: String,
    target_id: String,
    target_slug: Option(String),
    target_label: Option(String),
  )
}
