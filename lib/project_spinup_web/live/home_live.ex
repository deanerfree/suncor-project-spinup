defmodule ProjectSpinupWeb.HomeLive do
  use ProjectSpinupWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, allow_upload(socket, :pdf, accept: ~w(.pdf), max_entries: 1)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :pdf, ref)}
  end

  def handle_event("upload_pdf", _params, socket) do
    results =
      consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
        {:ok, ProjectSpinup.GenServer.submit_pdf(%{file_path: path, client_name: entry.client_name})}
      end)

    socket =
      case results do
        [{:ok, {:ok, _}}] -> put_flash(socket, :info, "PDF processed successfully")
        [{:ok, {:error, reason}}] -> put_flash(socket, :error, "Processing failed: #{inspect(reason)}")
        [] -> put_flash(socket, :error, "No file selected")
        _ -> put_flash(socket, :error, "Upload failed")
      end

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="w-screen h-screen flex items-center justify-center">
      <div class="flex flex-col gap-8 text-center">
        <h1 class="text-4xl font-bold mb-4">Welcome to Suncor Project Spinup!</h1>
        <p class="text-lg text-gray-600 mb-6">
          Your one-stop solution for Suncor core log project management.
        </p>
        <div id="requirements" class="flex flex-col items-center gap-4">
          <h2 class="text-2xl font-semibold">Required Files</h2>
          <div class="flex flex-col items-start gap-2">
            <div class="flex items-center gap-2">
              <input type="checkbox" id="am-report" class="mr-2" />
              <label for="am-report">
                AM Report
              </label>
            </div>
            <div class="flex items-center gap-2">
              <input type="checkbox" id="eor-report" class="mr-2" />
              <label for="eor-report">
                EOR Report
              </label>
            </div>
            <div class="flex items-center gap-2">
              <input type="checkbox" id="surface-descriptions" class="mr-2" />
              <label for="surface-descriptions">
                Surface Descriptions
              </label>
            </div>
          </div>
        </div>
        <form phx-submit="upload_pdf" phx-change="validate">
          <div
            id="drop-zone"
            phx-hook="DragNDropHook"
            phx-drop-target={@uploads.pdf.ref}
            class="space-y-4 space-x-4 border-4 border-dashed border-gray-300 rounded-lg p-12"
          >
            <div id="file-list" class="flex flex-col items-start gap-2">
              <%= for entry <- @uploads.pdf.entries do %>
                <div class="flex items-center gap-2">
                  <span><%= entry.client_name %></span>
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="text-red-500 hover:text-red-700"
                  >
                    &times;
                  </button>
                </div>
              <% end %>
            </div>
            <p>Drop in your stick diagram here</p>
            <.live_file_input upload={@uploads.pdf} class="hidden" />
            <label
              for={@uploads.pdf.ref}
              class="inline-block cursor-pointer px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition"
            >
              Browse for PDF
            </label>
          </div>
          <button
            type="submit"
            disabled={Enum.empty?(@uploads.pdf.entries)}
            class="mt-4 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Upload to Server
          </button>
        </form>
      </div>
    </div>
    """
  end
end
