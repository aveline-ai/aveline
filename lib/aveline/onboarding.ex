defmodule Aveline.Onboarding do
  @moduledoc """
  Agent-connected is a state, not a screen (see the onboarding TIP).

  A user counts as connected in a workspace once an agent acting as
  them has read the orientation doc — the last step of the setup
  prompt. Derived, never stored: it's the same DocViews signal the
  signup screen's live checkmark always used, generalized so every
  surface (home card, settings section) can ask the same question.
  """

  alias Aveline.Docs
  alias Aveline.DocViews

  def agent_connected?(workspace_id, user_id) do
    case Docs.get_orientation(workspace_id) do
      nil -> false
      orientation -> DocViews.agent_viewed?(orientation.base_doc_id, user_id)
    end
  end
end
