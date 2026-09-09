//// Milestones-domain test fixtures.

import aveline/milestones/milestone.{
  type Milestone, type NewMilestone, Milestone,
}
import gleam/option.{None}

pub fn milestone(id id: String, name name: String) -> Milestone {
  Milestone(
    id: id,
    name: name,
    date: "2026-07-06",
    description: None,
    created_at: "2026-07-06T12:00:00.000000Z",
  )
}

/// What a fake `insert` cap returns: the draft echoed back as a stored
/// row, so tests can assert exactly what the handler tried to insert.
pub fn stored(new: NewMilestone) -> Milestone {
  Milestone(
    id: "ms-1",
    name: new.name,
    date: new.date,
    description: new.description,
    created_at: "2026-07-06T12:00:00.000000Z",
  )
}
