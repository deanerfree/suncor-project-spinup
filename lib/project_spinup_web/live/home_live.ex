defmodule ProjectSpinupWeb.HomeLive do
  use ProjectSpinupWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket
      |> allow_upload(:pdf, accept: ~w(.pdf), max_entries: 1)
      |> assign(:result, nil)}
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
        [{:ok, pages}] ->
          socket
          |> put_flash(:info, "PDF processed successfully")
          |> assign(:result, pages)
        [{:error, reason}] -> put_flash(socket, :error, "Processing failed: #{inspect(reason)}")
        [] -> put_flash(socket, :error, "No file selected")
        _ -> put_flash(socket, :error, "Upload failed")
      end


    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="w-screen flex items-center justify-center">
      <div class="flex flex-col gap-8 text-center container p-8">
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
            <.live_file_input upload={@uploads.pdf} class="hidden" disabled={not Enum.empty?(@uploads.pdf.entries)} />
            <label
              for={@uploads.pdf.ref}
              class={[
                "inline-block px-4 py-2 bg-blue-600 text-white rounded transition",
                Enum.empty?(@uploads.pdf.entries) && "cursor-pointer hover:bg-blue-700",
                not Enum.empty?(@uploads.pdf.entries) && "opacity-50 cursor-not-allowed"
              ]}
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
        <%= if @result do %>
          <%= for page <- @result do %>
            <div class="mt-8 border rounded-lg p-4">
              <h2 class="text-xl font-bold"><%= page.well_name %></h2>
              <p>UWI: <%= page.uwi %></p>
              <p>Well ID: <%= page.well_id %></p>
              <p>Licence: <%= page.licence %></p>

              <%= for {section_name, section} <- page.sections, section != nil do %>
                <div class="mt-4">
                  <h3 class="font-semibold"><%= section_name %></h3>
                  <%= if Map.has_key?(section, :formations) do %>
                    <table class="w-full text-sm mt-2">
                      <thead>
                        <tr>
                          <th>Formation</th><th>MASL TVD</th><th>MKB TVD</th>
                          <th>Pressure (kPa)</th><th>EMW (kg/m³)</th><th>Drilling Problems</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for f <- section.formations do %>
                          <tr>
                            <td><%= f.formation %></td>
                            <td><%= f.masl_tvd %></td>
                            <td><%= f.mkb_tvd %></td>
                            <td><%= f.pressure_kpa %></td>
                            <td><%= f.emw_kg_m3 %></td>
                            <td><%= f.potential_drilling_problems %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  <% else %>
                    <pre class="text-xs whitespace-pre-wrap"><%= section.raw_text %></pre>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>

      </div>
    </div>
    """
  end
end
