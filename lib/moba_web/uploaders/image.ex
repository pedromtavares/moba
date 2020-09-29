defmodule Moba.Image do
  use Arc.Definition

  # Include ecto support (requires package arc_ecto installed):
  use Arc.Ecto.Definition

  alias MobaWeb.Endpoint
  alias Moba.Engine.Schema.Battler
  alias Moba.Game.Schema.{Avatar, Item}
  alias Moba.Accounts.Schema.Message

  @versions [:original]

  def __storage do
    if Application.get_env(:moba, :env) == :prod do
      Arc.Storage.S3
    else
      Arc.Storage.Local
    end
  end

  # To add a thumbnail version:
  # @versions [:original, :thumb]

  # Override the bucket on a per definition basis:
  # def bucket do
  #   :custom_bucket_name
  # end

  # Whitelist file extensions:
  # def validate({file, _}) do
  #   ~w(.jpg .jpeg .gif .png) |> Enum.member?(Path.extname(file.file_name))
  # end

  # Define a thumbnail transformation:
  # def transform(:thumb, _) do
  #   {:convert, "-strip -thumbnail 250x250^ -gravity center -extent 250x250 -format png", :png}
  # end

  # Override the persisted filenames:
  # def filename(version, _) do
  #   version
  # end

  # Override the storage directory:
  def storage_dir(_version, {_file, scope}) do
    code = Map.get(scope, :code) || scope["code"]
    "uploads/resources/#{code}"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(_version, scope) do
    struct = Map.get(scope, :__struct__)

    case struct do
      s when s in [Battler, Avatar, Message] -> Endpoint.url() <> "/images/default_avatar.png"
      Item -> Endpoint.url() <> "/images/default_item.png"
      _ -> Endpoint.url() <> "/images/default_skill.png"
    end
  end

  # Specify custom headers for s3 objects
  # Available options are [:cache_control, :content_disposition,
  #    :content_encoding, :content_length, :content_type,
  #    :expect, :expires, :storage_class, :website_redirect_location]
  #
  # def s3_object_headers(version, {file, scope}) do
  #   [content_type: MIME.from_path(file.file_name)]
  # end
end
