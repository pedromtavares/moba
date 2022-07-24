defmodule Moba.Accounts.Query.UserQuery do
  @moduledoc """
  Query functions for retrieving Users
  """

  alias Moba.Accounts.Schema.User

  import Ecto.Query

  def with_id(query \\ User, user_id) do
    from(u in query, where: u.id == ^user_id)
  end

  def inserted_recently(query \\ User, since_hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -since_hours_ago)

    from(user in query, where: user.inserted_at > ^ago, order_by: [desc: user.inserted_at])
  end

  def online_recently(query \\ User, since_hours_ago \\ 1) do
    ago = Timex.now() |> Timex.shift(hours: -since_hours_ago)

    from(u in query, where: u.last_online_at > ^ago)
  end
end
