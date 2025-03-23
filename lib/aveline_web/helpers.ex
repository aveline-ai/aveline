defmodule AvelineWeb.Helpers do
  @moduledoc """
  A module for helper functions.
  """

  require Aveline.Enums.AuthorKind
  alias Aveline.Enums
  alias Aveline.Structs.EnrichedChatRoomMessage

  def get_display_name(_, true, _), do: "You"

  def get_display_name(author_kind, _, user_display_name) do
    Enums.AuthorKind.map!(author_kind, %{
      Enums.AuthorKind.user() => user_display_name,
      Enums.AuthorKind.ai() => "Aveline"
    })
  end

  def same_author?(nil, _), do: false

  def same_author?(
        %EnrichedChatRoomMessage{author_kind: Enums.AuthorKind.ai()},
        %EnrichedChatRoomMessage{author_kind: Enums.AuthorKind.ai()}
      ),
      do: true

  def same_author?(
        %EnrichedChatRoomMessage{user_id: user_id_1},
        %EnrichedChatRoomMessage{user_id: user_id_2}
      )
      when user_id_1 == user_id_2,
      do: true

  def same_author?(_, _), do: false
end
