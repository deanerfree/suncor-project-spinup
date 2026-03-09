defmodule ProjectSpinupWeb.DownloadLive do
  use ProjectSpinupWeb, :live_view

  @max_age 300

  def mount(%{"token" => token}, _session, socket) do
    case Phoenix.Token.verify(ProjectSpinupWeb.Endpoint, "download", token, max_age: @max_age) do
      {:ok, file_path} ->
        {:ok, assign(socket, file_path: file_path, error: nil)}

      {:error, :expired} ->
        {:ok, assign(socket, file_path: nil, error: "Download link has expired")}

      {:error, _} ->
        {:ok, assign(socket, file_path: nil, error: "Invalid download link")}
    end
  end

  def handle_event("download", _params, socket) do
    {:noreply, push_event(socket, "download", %{url: "/files/#{socket.assigns.file_path}"})}
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @error do %>
        <p>{@error}</p>
      <% else %>
        <button phx-click="download">Download Report</button>
      <% end %>
    </div>
    """
  end
end
