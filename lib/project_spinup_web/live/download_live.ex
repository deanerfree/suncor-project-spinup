defmodule ProjectSpinupWeb.DownloadLive do
  use ProjectSpinupWeb, :live_view

  @max_age 300

  def mount(%{"token" => token}, _session, socket) do
    case Phoenix.Token.verify(ProjectSpinupWeb.Endpoint, "download", token, max_age: @max_age) do
      {:ok, file_paths} when is_list(file_paths) ->
        tokens =
          Enum.map(file_paths, fn path ->
            %{
              label: Path.basename(path),
              token: Phoenix.Token.sign(ProjectSpinupWeb.Endpoint, "download", path),
              size: file_size(path)
            }
          end)

        {:ok, assign(socket, files: tokens, error: nil)}

      {:ok, file_path} when is_binary(file_path) ->
        tokens = [
          %{
            label: Path.basename(file_path),
            token: Phoenix.Token.sign(ProjectSpinupWeb.Endpoint, "download", file_path),
            size: file_size(file_path)
          }
        ]

        {:ok, assign(socket, files: tokens, error: nil)}

      {:error, :expired} ->
        {:ok, assign(socket, files: [], error: "Download link has expired")}

      {:error, _} ->
        {:ok, assign(socket, files: [], error: "Invalid download link")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.workflow_header current_step={:download} />
    <div class="w-full flex flex-col gap-8 text-center p-8">
      <%= if @error do %>
        <p>{@error}</p>
      <% else %>
        <div class="w-full flex flex-col gap-4 text-lg font-medium">
          <h1 class="text-3xl font-bold mb-4">Your Downloads are Ready</h1>
          <p class="font-medium">Thank you for using the Project Spinup Tool.</p>
          <p>Your files are ready. Click the buttons below to download your reports.</p>
          <p>Note: These links will expire in 5 minutes.</p>
          <div class="flex flex-col gap-2 items-center mt-4 w-full max-w-lg mx-auto">
            <%= for file <- @files do %>
              <a
                href={"/download/file?token=#{file.token}"}
                download
                class="flex items-center gap-4 w-full px-4 py-3 rounded-lg border border-base-300 bg-base-100 hover:bg-base-200 transition-colors group"
              >
                <span class="shrink-0 text-green-600">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" class="w-8 h-8">
                    <path fill="#169154" d="M29,6H15.744C14.781,6,14,6.781,14,7.744v7.259h15V6z" />
                    <path fill="#18482a" d="M14,15.003h15V22h-15V15.003z" />
                    <path fill="#169154" d="M14,22h15v7H14V22z" />
                    <path fill="#18482a" d="M14,29h15v7.256C29,37.219,28.219,38,27.256,38H14V29z" />
                    <path fill="#29c27f" d="M42.256,6H29v9h13V7.744C42,6.781,41.219,6,42.256,6z" />
                    <path fill="#27663f" d="M29,15.003h13V22H29V15.003z" />
                    <path fill="#29c27f" d="M29,22h13v7H29V22z" />
                    <path fill="#27663f" d="M29,29h13v7.256C42,37.219,41.219,38,42.256,38H29V29z" />
                    <path
                      fill="#0c7238"
                      d="M6,42H26c1.105,0,2-0.895,2-2V28H4v12C4,41.105,4.895,42,6,42z"
                    />
                    <path
                      fill="#fff"
                      d="M9.962,37l-1.977-3.754L5.995,37H4l2.985-4.56L4.085,28h1.995l1.93,3.695L9.934,28h1.992l-2.947,4.352L12,37H9.962z"
                    />
                  </svg>
                </span>
                <div class="flex flex-col flex-1 text-left min-w-0">
                  <span class="text-sm font-medium truncate">{file.label}</span>
                  <span class="text-sm opacity-60">{file.size}</span>
                </div>
                <span class="shrink-0 opacity-50 group-hover:opacity-100 transition-opacity">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="w-5 h-5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                    />
                  </svg>
                </span>
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size >= 1_048_576 ->
        "#{Float.round(size / 1_048_576, 1)} MB"

      {:ok, %{size: size}} when size >= 1_024 ->
        "#{Float.round(size / 1_024, 1)} KB"

      {:ok, %{size: size}} ->
        "#{size} B"

      _ ->
        ""
    end
  end
end
