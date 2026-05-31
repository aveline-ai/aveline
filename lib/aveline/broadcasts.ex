defmodule Aveline.Broadcasts do
  @moduledoc """
  Central PubSub helper. Topics are keyed by stable identifiers
  (base_item_id for items, workspace_id for workspaces) so subscribers
  stay attached across edits.
  """

  alias Phoenix.PubSub

  @pubsub Aveline.PubSub

  def subscribe(topic) when is_binary(topic), do: PubSub.subscribe(@pubsub, topic)
  def unsubscribe(topic) when is_binary(topic), do: PubSub.unsubscribe(@pubsub, topic)

  def item_topic(base_item_id), do: "item:" <> base_item_id
  def item_messages_topic(base_item_id), do: "item:" <> base_item_id <> ":messages"
  def workspace_items_topic(workspace_id), do: "workspace:" <> workspace_id <> ":items"
  def workspace_views_topic(workspace_id), do: "workspace:" <> workspace_id <> ":views"

  def publish_item_event(event, %{base_item_id: base, workspace_id: ws_id} = item)
      when event in [:item_created, :item_updated, :item_deleted, :item_restored] do
    PubSub.broadcast(@pubsub, item_topic(base), {event, item})
    PubSub.broadcast(@pubsub, workspace_items_topic(ws_id), {event, item})
    :ok
  end

  def publish_view_event(event, %{workspace_id: ws_id} = view)
      when event in [:view_created, :view_updated, :view_deleted, :view_restored] do
    PubSub.broadcast(@pubsub, workspace_views_topic(ws_id), {event, view})
  end
end
