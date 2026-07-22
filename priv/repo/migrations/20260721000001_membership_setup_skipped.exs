defmodule Aveline.Repo.Migrations.MembershipSetupSkipped do
  use Ecto.Migration

  # Onboarding de-escalation: the setup hero dominates home until the
  # user connects an agent or explicitly skips; a skip collapses it to
  # the compact card. The skip is user-expressed state, per user per
  # workspace — the membership row is its natural home.
  def change do
    alter table(:workspace_memberships) do
      add :setup_skipped_at, :utc_datetime_usec
    end
  end
end
