defmodule AvelineWeb.UIHelpers do
  @moduledoc """
  Tiny formatting helpers shared across views: relative timestamps,
  initials for avatars, etc.
  """

  @doc """
  Render a `DateTime` Notion-style: precise for very recent moments, then
  calendar-aware ("Today", "Yesterday", "Tuesday") for the last week, then
  a short date, then a full date once it's old enough to need the year.

      0–59 sec ago       → "just now"
      < 1 hour           → "5m ago"
      same calendar day  → "2h ago"      (still useful precision the same day)
      previous cal. day  → "Yesterday"
      2–6 cal. days back → "Tuesday"     (just the weekday name)
      this year          → "Mar 12"
      older              → "Mar 12, 2026"

  All calendar boundaries use UTC — close enough until we plumb user
  timezones through.
  """
  def relative_time(nil), do: ""

  def relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_sec = DateTime.diff(now, dt, :second)
    day_diff = Date.diff(DateTime.to_date(now), DateTime.to_date(dt))

    cond do
      diff_sec < 60 -> "just now"
      diff_sec < 3600 -> "#{div(diff_sec, 60)}m ago"
      day_diff == 0 -> "#{div(diff_sec, 3600)}h ago"
      day_diff == 1 -> "Yesterday"
      day_diff in 2..6 -> weekday_name(dt)
      same_year?(dt, now) -> Calendar.strftime(dt, "%b %-d")
      true -> Calendar.strftime(dt, "%b %-d, %Y")
    end
  end

  defp weekday_name(%DateTime{} = dt), do: Calendar.strftime(dt, "%A")
  defp same_year?(%DateTime{year: y}, %DateTime{year: y}), do: true
  defp same_year?(_, _), do: false

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
