defmodule Test.HTTPFixturePlug do
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(owner), do: owner

  @impl true
  def call(conn, owner) do
    {:ok, body, conn} = read_body(conn)
    send(owner, {:http_request, conn.method, conn.request_path, conn.req_headers, body})

    respond(conn)
  end

  defp respond(%{request_path: "/oauth/token"} = conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{access_token: "fixture-token", token_type: "Bearer"}))
  end

  defp respond(conn) do
    conn = put_resp_header(conn, "content-type", "application/octet-stream")

    conn =
      if conn.request_path == "/download" do
        put_resp_header(conn, "content-disposition", ~s(attachment; filename="fixture.webp"))
      else
        conn
      end

    send_resp(conn, 200, if(conn.method in ["HEAD", "PUT"], do: "", else: "fixture-body"))
  end
end
