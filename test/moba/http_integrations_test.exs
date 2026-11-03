defmodule Moba.HTTPIntegrationsTest do
  use ExUnit.Case, async: false

  setup do
    server = start_supervised!({Bandit, plug: {Test.HTTPFixturePlug, self()}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    %{url: "http://127.0.0.1:#{port}", port: port}
  end

  test "ExAws uploads signed objects through Req", %{port: port} do
    assert Application.fetch_env!(:ex_aws, :http_client) == ExAws.Request.Req
    operation = ExAws.S3.put_object("fixture-bucket", "fixture.webp", "uploaded-image")

    assert {:ok, %{status_code: 200}} =
             ExAws.request(operation,
               access_key_id: "fixture-access-key",
               secret_access_key: "fixture-secret-key",
               region: "us-east-1",
               host: "127.0.0.1",
               port: port,
               scheme: "http://"
             )

    assert_receive {:http_request, "PUT", "/fixture-bucket/fixture.webp", headers, "uploaded-image"}
    assert List.keyfind(headers, "authorization", 0)
  end

  test "Waffle downloads artwork through Req and retains the supplied filename", %{url: url} do
    assert Application.fetch_env!(:waffle, :http_client) == Waffle.HTTPClient.Req
    assert %Waffle.File{file_name: "fixture.webp", path: path} = Waffle.File.new(url <> "/download", Moba.Image)
    on_exit(fn -> File.rm(path) end)

    assert File.read!(path) == "fixture-body"
    assert_receive {:http_request, "GET", "/download", _, ""}
  end

  test "Sentry's configured client retains its response contract", %{url: url} do
    client = Sentry.Config.client()
    assert {:ok, 200, _headers, "fixture-body"} = client.post(url <> "/envelope", [], "fixture-envelope")
    assert_receive {:http_request, "POST", "/envelope", _, "fixture-envelope"}
  end

  test "Swoosh sends API requests through Req", %{url: url} do
    assert Application.fetch_env!(:swoosh, :api_client) == Swoosh.ApiClient.Req

    assert {:ok, 200, _headers, "fixture-body"} =
             Swoosh.ApiClient.Req.post(url <> "/email", [], "fixture-email", Swoosh.Email.new())

    assert_receive {:http_request, "POST", "/email", _, "fixture-email"}
  end

  test "the OAuth client used by Discord can exchange tokens without Hackney", %{url: url} do
    client =
      OAuth2.Client.new(
        client_id: "fixture-client",
        client_secret: "fixture-secret",
        site: url,
        token_url: "/oauth/token"
      )
      |> OAuth2.Client.put_serializer("application/json", Jason)

    assert {:ok, %{token: %{access_token: "fixture-token"}}} = OAuth2.Client.get_token(client, code: "fixture-code")
    assert_receive {:http_request, "POST", "/oauth/token", _, body}
    assert URI.decode_query(body)["code"] == "fixture-code"
  end

  test "Tzdata's HTTP adapter supports update checks and downloads", %{url: url} do
    assert {:ok, {200, _headers}} = Tzdata.HTTPClient.Httpc.head(url, [], [])
    assert {:ok, {200, _headers, "fixture-body"}} = Tzdata.HTTPClient.Httpc.get(url, [], [])
    assert_receive {:http_request, "HEAD", "/", _, ""}
    assert_receive {:http_request, "GET", "/", _, ""}
  end
end
