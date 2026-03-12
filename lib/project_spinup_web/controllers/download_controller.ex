defmodule ProjectSpinupWeb.DownloadController do
  use ProjectSpinupWeb, :controller

  @max_age 300

  def file(conn, %{"token" => token}) do
    case Phoenix.Token.verify(ProjectSpinupWeb.Endpoint, "download", token, max_age: @max_age) do
      {:ok, file_path} ->
        filename = Path.basename(file_path)

        conn
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_file(200, file_path)

      {:error, :expired} ->
        conn
        |> put_status(403)
        |> text("Download link has expired")

      {:error, _} ->
        conn
        |> put_status(403)
        |> text("Invalid download link")
    end
  end
end
