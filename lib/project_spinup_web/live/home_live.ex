defmodule ProjectSpinupWeb.HomeLive do
  use ProjectSpinupWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_upload(:pdf, accept: ~w(.pdf), max_entries: 1)
     |> assign(:result, nil)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :pdf, ref)}
  end

  def handle_event("clear_result", _params, socket) do
    {:noreply, assign(socket, :result, nil)}
  end

  def handle_event("upload_pdf", _params, socket) do
    # consume_uploaded_entries requires the callback to return {:ok, value} or {:error, reason}.
    # submit_pdf already returns {:ok, pages} | {:error, reason}, so pass it through directly
    # rather than wrapping it again in {:ok, ...} which would produce {:ok, {:ok, pages}}.
    results =
      consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
        {:ok,
         ProjectSpinup.GenServer.submit_pdf(%{file_path: path, client_name: entry.client_name})}
      end)

    socket =
      case results do
        [{:ok, pages}] ->
          socket
          |> put_flash(:info, "PDF processed successfully")
          |> assign(:result, pages)

        [{:error, reason}] ->
          put_flash(socket, :error, "Processing failed: #{inspect(reason)}")

        [] ->
          put_flash(socket, :error, "No file selected")

        _ ->
          put_flash(socket, :error, "Upload failed")
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
              <label for="am-report">AM Report</label>
            </div>
            <div class="flex items-center gap-2">
              <input type="checkbox" id="eor-report" class="mr-2" />
              <label for="eor-report">EOR Report</label>
            </div>
            <div class="flex items-center gap-2">
              <input type="checkbox" id="surface-descriptions" class="mr-2" />
              <label for="surface-descriptions">Surface Descriptions</label>
            </div>
          </div>
        </div>

        <form phx-submit="upload_pdf" phx-change="validate">
          <div
            id="drop-zone"
            phx-hook="DragNDropHook"
            phx-drop-target={@uploads.pdf.ref}
            class="flex flex-col items-center justify-center space-y-4 space-x-4 border-4 h-64 w-full border-dashed border-gray-300 rounded-lg p-12"
          >
            <div id="file-list" class="flex flex-col justify-center w-full gap-2">
              <%= for entry <- @uploads.pdf.entries do %>
                <div class="flex items-center justify-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="ionicon text-gray-400" width="16" height="18" viewBox="0 0 512 512">
                    <path d="M416 221.25V416a48 48 0 01-48 48H144a48 48 0 01-48-48V96a48 48 0 0148-48h98.75a32 32 0 0122.62 9.37l141.26 141.26a32 32 0 019.37 22.62z" fill="none" stroke="currentColor" stroke-linejoin="round" stroke-width="64"/>
                    <path d="M256 56v120a32 32 0 0032 32h120" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="64"/>
                  </svg>
                  <span class="font-medium text-lg text-gray-400">{entry.client_name}</span>
                  <button
                    type="button"
                    class="font-medium text-gray-400 hover:text-gray-700 hover:cursor-pointer"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                  >
                    &times;
                  </button>
                </div>
              <% end %>
            </div>
            <.live_file_input
              upload={@uploads.pdf}
              class="hidden"
              disabled={not Enum.empty?(@uploads.pdf.entries)}
            />
            <%= if @uploads.pdf.entries == [] do %>
              <p>Drop in your stick diagram here</p>
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
            <% end %>
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
              <h2 class="text-xl font-bold">{page.well_name}</h2>
              <p>UWI: {page.uwi}</p>
              <p>Well ID: {page.well_id}</p>
              <p>Licence: {page.licence}</p>

              <%= for {section_name, section} <- page.sections, section != nil do %>
                <div class="mt-4 text-left">
                  <h3 class="font-semibold">{section_name}</h3>

                  <%= cond do %>
                    <% Map.has_key?(section, :formations) -> %>
                      <table class="w-full text-sm mt-2 border-collapse">
                        <thead>
                          <tr class="bg-gray-100">
                            <th class="border px-2 py-1">Formation</th>
                            <th class="border px-2 py-1">MASL TVD</th>
                            <th class="border px-2 py-1">MKB TVD</th>
                            <th class="border px-2 py-1">Pressure (kPa)</th>
                            <th class="border px-2 py-1">EMW (kg/m³)</th>
                            <th class="border px-2 py-1">Drilling Problems</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for f <- section.formations do %>
                            <tr>
                              <td class="border px-2 py-1">{f.formation}</td>
                              <td class="border px-2 py-1">{f.masl_tvd}</td>
                              <td class="border px-2 py-1">{f.mkb_tvd}</td>
                              <td class="border px-2 py-1">{f.pressure_kpa}</td>
                              <td class="border px-2 py-1">{f.emw_kg_m3}</td>
                              <td class="border px-2 py-1">{f.potential_drilling_problems}</td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% Map.has_key?(section, :columns) -> %>
                      <% cols = section.columns
                      # Zip the three columns together, padding shorter lists with ""
                      max_len =
                        [cols.tool_types, cols.runs, cols.notes] |> Enum.map(&length/1) |> Enum.max()

                      pad = fn list -> list ++ List.duplicate("", max_len - length(list)) end
                      rows = Enum.zip([pad.(cols.tool_types), pad.(cols.runs), pad.(cols.notes)]) %>
                      <table class="w-full text-sm mt-2 border-collapse">
                        <thead>
                          <tr class="bg-gray-100">
                            <th class="border px-2 py-1 text-left">Tool Type</th>
                            <th class="border px-2 py-1 text-left">Run in Well</th>
                            <th class="border px-2 py-1 text-left">Notes</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for {tool, run, note} <- rows do %>
                            <tr>
                              <td class="border px-2 py-1">{tool}</td>
                              <td class="border px-2 py-1">{run}</td>
                              <td class="border px-2 py-1">{note}</td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% true -> %>
                      <pre class="text-xs whitespace-pre-wrap text-left"><%= section.raw_text %></pre>
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
