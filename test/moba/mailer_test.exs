defmodule Moba.MailerTest do
  use ExUnit.Case

  test "Resend receives the configured sender, both bodies and the inline helmet" do
    previous_client = Application.fetch_env(:swoosh, :api_client)
    Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)

    on_exit(fn ->
      case previous_client do
        {:ok, client} -> Application.put_env(:swoosh, :api_client, client)
        :error -> Application.delete_env(:swoosh, :api_client)
      end
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.host == "api.resend.com"
      assert conn.request_path == "/emails"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer re_test_key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["from"] == "My MOBA <noreply@example.com>"
      assert payload["to"] == ["hero@example.com"]
      assert payload["html"] =~ "cid:browsermoba-helmet"
      assert payload["html"] =~ "https://example.com/reset/example-token"
      assert payload["text"] =~ "https://example.com/reset/example-token"

      assert [%{"content_id" => "browsermoba-helmet", "filename" => "helmet.png", "content" => content}] =
               payload["attachments"]

      assert Base.decode64!(content) == File.read!(Application.app_dir(:moba, "priv/emails/helmet.png"))
      Req.Test.json(conn, %{id: "test-email-id"})
    end)

    email =
      Moba.Emails.UserEmail.build(
        %{email: "hero@example.com", username: "Hero"},
        "https://example.com/reset/example-token",
        :reset_password,
        {"My MOBA", "noreply@example.com"}
      )
      |> Swoosh.Email.put_private(:client_options, plug: {Req.Test, __MODULE__})

    assert {:ok, %{id: "test-email-id"}} =
             Moba.Mailer.deliver(email, adapter: Swoosh.Adapters.Resend, api_key: "re_test_key")
  end

  test "production account links use HTTPS without an explicit port" do
    config = Config.Reader.read!("config/prod.exs", env: :prod)
    url = config[:moba][MobaWeb.Endpoint][:url]
    uri = %URI{scheme: url[:scheme], host: url[:host], port: url[:port]}

    for {kind, path} <- [
          {:reset_password, "/users/reset_password/example-token"},
          {:confirmation, "/users/confirm/example-token"},
          {:update_email, "/users/settings/confirm_email/example-token"}
        ] do
      link = Phoenix.VerifiedRoutes.unverified_url(uri, path)
      assert link == "https://browsermoba.com" <> path

      email =
        Moba.Emails.UserEmail.build(
          %{email: "hero@example.com", username: "Hero"},
          link,
          kind,
          {"My MOBA", "noreply@example.com"}
        )

      assert email.text_body =~ link

      assert email.html_body
             |> LazyHTML.from_document()
             |> LazyHTML.query("#email-action")
             |> LazyHTML.attribute("href") == [link]
    end
  end

  test "production loads Resend credentials at runtime and requires RESEND_KEY" do
    variables = ["RESEND_KEY", "DATABASE_URL", "SECRET_KEY_BASE"]
    previous = Map.new(variables, &{&1, System.get_env(&1)})

    try do
      System.put_env("RESEND_KEY", "re_runtime_test_key")
      System.put_env("DATABASE_URL", "ecto://postgres:postgres@localhost/moba_test")
      System.put_env("SECRET_KEY_BASE", String.duplicate("a", 64))

      config = Config.Reader.read!("config/runtime.exs", env: :prod)
      assert config[:moba][Moba.Mailer][:adapter] == Swoosh.Adapters.Resend
      assert config[:moba][Moba.Mailer][:api_key] == "re_runtime_test_key"

      System.delete_env("RESEND_KEY")

      assert_raise RuntimeError, ~r/environment variable RESEND_KEY is missing/, fn ->
        Config.Reader.read!("config/runtime.exs", env: :prod)
      end
    after
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end
  end
end
