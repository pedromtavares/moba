defmodule Moba.Utils do
  def run_async(fun) do
    if test?() do
      fun.()
    else
      Task.start(fun)
    end
  end

  def struct_from_map(a_map, as: a_struct) do
    # Find the keys within the map
    keys =
      Map.keys(a_struct)
      |> Enum.filter(fn x -> x != :__struct__ end)

    # Process map, checking for both string / atom keys
    processed_map =
      for key <- keys, into: %{} do
        value = Map.get(a_map, key) || Map.get(a_map, to_string(key))
        {key, value}
      end

    a_struct = Map.merge(a_struct, processed_map)
    a_struct
  end

  def username(%{bot_options: %{name: name}}), do: name
  def username(%{user: %{username: username}}), do: username
  def username(_), do: "Guest"

  defp test?, do: Application.get_env(:moba, :env) == :test
end
