//// Milestones IO capabilities. Built for real in
//// lib/aveline/gleam/caps/milestones.ex; keep the two in lockstep
//// (tag + field order).

import aveline/milestones/milestone.{type Milestone, type NewMilestone}
import gleam/option.{type Option}

pub type MilestonesCaps {
  MilestonesCaps(
    /// Active (non-deleted) milestones for a workspace, date asc then
    /// created asc.
    list_active: fn(String) -> List(Milestone),
    /// Insert a validated milestone; returns the stored row.
    insert: fn(NewMilestone) -> Milestone,
    /// Id of the active milestone (workspace_id, id), if one exists.
    find_active: fn(String, String) -> Option(String),
    /// Soft-delete a milestone: (milestone_id, deleted_by user id).
    soft_delete: fn(String, String) -> Nil,
  )
}

pub fn stub() -> MilestonesCaps {
  MilestonesCaps(
    list_active: fn(_) { panic as "stub milestones.list_active" },
    insert: fn(_) { panic as "stub milestones.insert" },
    find_active: fn(_, _) { panic as "stub milestones.find_active" },
    soft_delete: fn(_, _) { panic as "stub milestones.soft_delete" },
  )
}
