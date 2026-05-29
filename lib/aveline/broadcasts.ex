defmodule Aveline.Broadcasts do
  @moduledoc """
  Central PubSub helper.

  Every mutating context function publishes a tagged event via this module so
  LiveViews (and any other process) can subscribe to a stable topic surface
  without depending on the Aveline.PubSub server name.

  ## Topic conventions

  Topics are namespaced by entity scope so a subscriber can listen at the
  granularity it cares about. The current set:

    * `"item:" <> item_id <> ":messages"` — message events for a single item
    * `"item:" <> item_id`               — item-level events (update, delete, pin/unpin)
    * `"workspace:" <> ws_id <> ":items"` — every item event in a workspace
    * `"workspace:" <> ws_id <> ":views"` — every view event in a workspace

  ## Event shape

  All events are 2-tuples of `{event_atom, payload}`. The atom names the
  thing that happened; the payload is the affected struct (preloads
  included where the context already loaded them).

      {:message_created, %ItemMessage{}}
      {:message_updated, %ItemMessage{}}
      {:message_deleted, %ItemMessage{}}
      {:item_updated,    %Item{}}
      {:item_deleted,    %Item{}}
      ...

  Subscribers receive these as plain process messages via `handle_info/2`.
  """

  alias Phoenix.PubSub

  @pubsub Aveline.PubSub

  # ===== Subscribe / Unsubscribe =====

  def subscribe(topic) when is_binary(topic), do: PubSub.subscribe(@pubsub, topic)
  def unsubscribe(topic) when is_binary(topic), do: PubSub.unsubscribe(@pubsub, topic)

  # ===== Topic builders =====

  def item_topic(item_id), do: "item:" <> item_id
  def item_messages_topic(item_id), do: "item:" <> item_id <> ":messages"
  def workspace_items_topic(workspace_id), do: "workspace:" <> workspace_id <> ":items"
  def workspace_views_topic(workspace_id), do: "workspace:" <> workspace_id <> ":views"

  # ===== Publishers =====

  def publish_message_event(event, %{item_id: item_id} = message)
      when event in [:message_created, :message_updated, :message_deleted] do
    PubSub.broadcast(@pubsub, item_messages_topic(item_id), {event, message})
  end

  def publish_item_event(event, %{id: id, workspace_id: ws_id} = item)
      when event in [:item_created, :item_updated, :item_deleted, :item_restored] do
    PubSub.broadcast(@pubsub, item_topic(id), {event, item})
    PubSub.broadcast(@pubsub, workspace_items_topic(ws_id), {event, item})
    :ok
  end

  def publish_view_event(event, %{workspace_id: ws_id} = view)
      when event in [:view_created, :view_updated, :view_deleted, :view_restored] do
    PubSub.broadcast(@pubsub, workspace_views_topic(ws_id), {event, view})
  end
end
