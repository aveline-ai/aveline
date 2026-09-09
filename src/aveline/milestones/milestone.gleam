//// Milestone domain types — dated workspace facts (a release shipped,
//// a pricing change) that annotate every time-series chart spanning
//// them. Soft-delete only, no version chain.

import gleam/option.{type Option}

/// A stored milestone as the API echoes it. `date` is an ISO8601
/// calendar date and `created_at` an ISO8601 datetime — timestamps
/// cross the boundary as display strings.
pub type Milestone {
  Milestone(
    id: String,
    name: String,
    date: String,
    description: Option(String),
    created_at: String,
  )
}

/// A validated milestone ready to insert.
pub type NewMilestone {
  NewMilestone(
    workspace_id: String,
    name: String,
    date: String,
    description: Option(String),
    created_by: String,
  )
}
