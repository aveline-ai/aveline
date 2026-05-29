defmodule AvelineWeb.UIHelpers do
  @moduledoc """
  Tiny formatting helpers shared across views: relative timestamps,
  initials for avatars, etc.
  """

  @doc """
  Render a `DateTime` as a short relative string ("2h ago", "yesterday",
  "Mar 12, 2026"). Anything older than ~7 days falls back to an absolute
  date.
  """
  def relative_time(nil), do: ""

  def relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 172_800 -> "yesterday"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%b %-d, %Y")
    end
  end

  @doc """
  Long absolute timestamp for tooltips ("Mar 12, 2026 at 3:42 PM UTC").
  """
  def absolute_time(nil), do: ""

  def absolute_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y at %-I:%M %p UTC")
  end

  @doc """
  First character of a username, uppercased — for avatar circles.
  """
  def initial(nil), do: "?"
  def initial(""), do: "?"
  def initial(username) when is_binary(username), do: String.first(username) |> String.upcase()

  @doc """
  Deterministic accent color for a user — same username always maps to the
  same hue, so avatars feel consistent.
  """
  def avatar_hue(nil), do: 240
  def avatar_hue(""), do: 240

  def avatar_hue(username) when is_binary(username) do
    rem(:erlang.phash2(username), 360)
  end
end
