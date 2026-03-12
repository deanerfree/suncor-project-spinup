defmodule ProjectSpinupWeb.DownloadLive do
  use ProjectSpinupWeb, :live_view

  @max_age 300

  def mount(%{"token" => token}, _session, socket) do
    case Phoenix.Token.verify(ProjectSpinupWeb.Endpoint, "download", token, max_age: @max_age) do
      {:ok, file_path} ->
        {:ok, assign(socket, file_path: file_path, token: token, error: nil)}

      {:error, :expired} ->
        {:ok, assign(socket, file_path: nil, token: nil, error: "Download link has expired")}

      {:error, _} ->
        {:ok, assign(socket, file_path: nil, token: nil, error: "Invalid download link")}
    end
  end

  def handle_event("download", _params, socket) do
    {:noreply, push_event(socket, "download", %{url: "/download/file?token=#{socket.assigns.token}"})}
  end

  def render(assigns) do
    ~H"""
    <div class="w-full flex flex-col gap-8 text-center p-8">
      <%= if @error do %>
        <p>{@error}</p>
      <% else %>
        <div class="w-full flex flex-col gap-4 text-lg font-medium">
          <h1 class="text-3xl font-bold mb-4">Your Download is Ready</h1>
          <p class="font-medium">Thank you for using the Project Spinup Tool.</p>
          <p>Your download is ready. Click the button below to download your report.</p>
          <p>Note: This link will expire in 5 minutes.</p>
          <div id="download-link" phx-hook="DownloadHook"></div>
          <button class="btn btn-primary" phx-click="download">Download Report</button>
        </div>
      <% end %>
    </div>
    """
  end
end
