defmodule ProjectSpinupWeb.ResultsLive do
  @moduledoc """
    LiveView to display the results of the PDF parsing and template population. This will be the final step in the project spinup process where the user can review the extracted data and download the populated templates.
  """
  use ProjectSpinupWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :result, nil)}
  end

  def handle_event("load_result", %{"data" => data}, socket) do
    result = atomize_keys(data)
    {:noreply, assign(socket, :result, result)}
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {String.to_atom(k), atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(value), do: value

  def render(assigns) do
    ~H"""
    <div id="well-storage" phx-hook="LocalStorageHook"></div>
    <div class="w-screen flex flex-col items-center justify-center container">
      <%= if @result do %>
        <div class="w-full flex flex-col gap-8 text-center p-8">
          <h1 class="text-3xl font-bold mb-4">Parsed Well Stick Data</h1>
          <div class="flex flex-col gap-4 text-lg font-medium">
            <p class="font-medium">Review the extracted data below.</p>
            <p class="">If you see any issues please edit</p>
          </div>
        </div>
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
      <% else %>
        <div class="mt-8 border rounded-lg p-4">
          <h2 class="text-xl font-bold">No results to display</h2>
          <p>Please upload a PDF to see the results.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
