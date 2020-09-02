defmodule Moba.Accounts.Messages do
  @moduledoc """
  Manages Messages for the sidebar Chat
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.Message

  import Ecto.Query, only: [from: 2]

  @doc """
  Pulls messages from the latest day only
  """
  def latest(limit) do
    ago = Timex.now() |> Timex.shift(hours: -24)

    query =
      from message in Message,
        where: message.inserted_at > ^ago,
        limit: ^limit,
        order_by: [desc: :id]

    Repo.all(query)
  end

  def get!(id), do: Repo.get!(Message, id)

  def change(attrs), do: Message.changeset(%Message{}, attrs)

  def create!(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert!()
  end

  def delete(%Message{} = message), do: Repo.delete(message)
end
