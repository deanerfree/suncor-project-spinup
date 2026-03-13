defmodule ProjectSpinupWeb.ResultsLive do
  @moduledoc """
    LiveView to display the results of the PDF parsing and template population. This will be the final step in the project spinup process where the user can review the extracted data and download the populated templates.
  """
  use ProjectSpinupWeb, :live_view
  alias ProjectSpinup.GenServer

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :result, nil)}
  end

  def handle_event("load_result", %{"data" => data}, socket) do
    result = atomize_keys(data)
    {:noreply, assign(socket, :result, result)}
  end

  def handle_event("generate_excel_files", params, socket) do
    rig_details =
      Map.take(params, [
        "rig_name",
        "spud_date",
        "og",
        "og_ph",
        "geo_day",
        "geo_day_ph",
        "geo_night",
        "geo_night_ph",
        "wss_day",
        "wss_night",
        "rig_ph"
      ])
      |> Map.update("spud_date", "", fn date ->
        case Date.from_iso8601(date) do
          {:ok, d} -> Calendar.strftime(d, "%m/%d/%Y")
          _ -> date
        end
      end)
    enriched_result = Enum.map(socket.assigns.result, &Map.put(&1, :rig_details, rig_details))
    results = GenServer.populate_template(enriched_result)

    socket =
      case results do
        {:ok, %{file_paths: file_paths}} ->
          token = Phoenix.Token.sign(ProjectSpinupWeb.Endpoint, "download", file_paths)

          socket
          |> put_flash(:info, "Excel files generated successfully")
          |> push_navigate(to: ~p"/download?token=#{token}")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to generate Excel files: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {String.to_atom(k), atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(value), do: value

  @section_order [
    "Surface Location Information",
    "Geological Formation Information",
    "Drill Cutting / Coring Information",
    "Drilling Fluids",
    "Drilling Notes",
    "Casing Design",
    "Logging Information",
    "General Information",
    "Piezometer Design",
    "Thermocouple Design",
    "Cementing",
    "Casing Accessories"
  ]

  defp ordered_sections(sections) do
    known =
      Enum.flat_map(@section_order, fn name ->
        case Map.get(sections, String.to_atom(name)) do
          nil -> []
          section -> [{name, section}]
        end
      end)

    unknown =
      sections
      |> Enum.reject(fn {k, _} -> Atom.to_string(k) in @section_order end)
      |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)

    known ++ unknown
  end

  defp section_type(section) do
    cond do
      Map.has_key?(section, :location) ->
        :location

      Map.has_key?(section, :casing) ->
        :casing

      Map.has_key?(section, :rows) and match?([%{formation: _} | _], section.rows) ->
        :geo_formations

      Map.has_key?(section, :rows) and match?([%{hole_section: _} | _], section.rows) ->
        :drilling_fluids

      Map.has_key?(section, :columns) ->
        :logging

      # return nil for Thermocouple, Cementing, Casing Accessories

      true ->
        :raw
    end
  end

  def render(assigns) do
    ~H"""
    <div id="well-storage" phx-hook="LocalStorageHook" data-key="well_stick"></div>
    <div class="w-screen flex flex-col items-center justify-center container">
      <%= if @result do %>
        <div class="w-full flex flex-col gap-8 text-center p-8">
          <h1 class="text-3xl font-bold mb-4">Parsed Well Stick Data</h1>
          <div class="flex flex-col gap-4 text-lg font-medium">
            <p class="font-medium">Review the following data that has been extracted.</p>
            <p class="">
              If you see any issues please make the necessary changes before populating the excel files
            </p>
            <p>
              >
              Once you are satisfied with the data, click the "Generate Excel Files" button to download the populated templates.
            </p>
          </div>
        </div>

        <form phx-submit="generate_excel_files" class="w-full flex flex-col gap-8">
          <div id="rig-details" phx-hook="LocalStorageHook" data-key="rig_details" class="w-full flex flex-col gap-8 text-center p-4 border rounded-lg">
            <h2 class="font-bold uppercase">Rig details</h2>
            <div class="gap-4 grid grid-cols-2">
              <.input type="text" name="rig_name" label="Rig Name" value=""></.input>
              <.input type="date" name="spud_date" label="Spud Date" value=""></.input>
              <div class="col-span-2 flex flex-col gap-4 text-left border rounded-lg p-4">
                <h3 class="font-semibold col-span-2">Geology Contact Information</h3>
                <h4 class="font-semibold">Office Geologist</h4>
                <div class="flex text-left w-full gap-4">
                  <div class="text-left w-1/2">
                    <.input type="text" name="og" label="Office Geologist" value=""></.input>
                    <.phone_input id="og-ph" name="og_ph" label="Phone Number" />
                  </div>
                </div>
                <h4 class="font-semibold">Wellsite Geology Team</h4>
                <div class="flex text-left w-full gap-4">
                  <div class="text-left w-1/2">
                    <.input type="text" name="geo_day" label="Geologist Days" value=""></.input>
                    <.phone_input id="geo-day-ph" name="geo_day_ph" label="Geologist Days Phone Number" />
                  </div>
                  <div class="text-left w-1/2">
                    <.input type="text" name="geo_night" label="Geologist Night" value=""></.input>
                    <.phone_input id="geo-night-ph" name="geo_night_ph" label="Geologist Nights Phone Number" />
                  </div>
                </div>
              </div>
              <div class="col-span-2 flex flex-col gap-4 text-left border rounded-lg p-4">
                <h3 class="font-semibold col-span-2">Well Site Supervisors</h3>
                <div class="text-left w-1/2">
                  <.input type="text" name="wss_day" label="WSS Days" value=""></.input>
                </div>
                <div class="text-left w-1/2">
                  <.input type="text" name="wss_night" label="WSS Night" value=""></.input>
                </div>
                <div>
                  <.phone_input id="rig-ph" name="rig_ph" label="Rig Phone Number" />
                </div>
              </div>
            </div>
          </div>

          <%= for page <- @result do %>
            <div class="mt-8 border rounded-lg p-4">
              <h2 class="text-xl font-bold">{page.well_name}</h2>
              <p>UWI: {page.uwi}</p>
              <p>Well ID: {page.well_id}</p>
              <p>Licence: {page.licence}</p>

              <%= for {section_name, section} <- ordered_sections(page.sections), section != nil do %>
                <div class="mt-4 text-left">
                  <h3 class="font-semibold">{section_name}</h3>

                  <%= case section_type(section) do %>
                    <% :location -> %>
                      <div class="mt-2 flex gap-8 text-sm">
                        <table class="border-collapse">
                          <tbody>
                            <tr>
                              <td class="pr-4 py-0.5 text-gray-500">Ground Level (masl)</td>
                              <td class="border-b px-2 py-0.5 font-mono">
                                {section.location.elevation.ground_level_masl}
                              </td>
                            </tr>
                            <tr>
                              <td class="pr-4 py-0.5 text-gray-500">KB - Ground Level (m)</td>
                              <td class="border-b px-2 py-0.5 font-mono">
                                {section.location.elevation.kb_ground_level_m}
                              </td>
                            </tr>
                            <tr>
                              <td class="pr-4 py-0.5 text-gray-500">KB Elevation (mSS)</td>
                              <td class="border-b px-2 py-0.5 font-mono">
                                {section.location.elevation.kb_elevation_mss}
                              </td>
                            </tr>
                          </tbody>
                        </table>
                        <table class="border-collapse">
                          <thead>
                            <tr>
                              <th colspan="2" class="text-left text-gray-500 font-normal pb-1">
                                {section.location.coordinates.system}
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr>
                              <td class="pr-4 py-0.5 text-gray-500">Northing</td>
                              <td class="border-b px-2 py-0.5 font-mono">
                                {section.location.coordinates.northing}
                              </td>
                            </tr>
                            <tr>
                              <td class="pr-4 py-0.5 text-gray-500">Easting</td>
                              <td class="border-b px-2 py-0.5 font-mono">
                                {section.location.coordinates.easting}
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                    <% :casing -> %>
                      <% has_int = "intermediate" in section.casing.columns %>
                      <table class="w-full text-sm mt-2 border-collapse">
                        <thead>
                          <tr class="bg-gray-100">
                            <th class="border px-2 py-1 text-left">Field</th>
                            <th class="border px-2 py-1">Surface</th>
                            <%= if has_int do %>
                              <th class="border px-2 py-1">Intermediate</th>
                            <% end %>
                            <th class="border px-2 py-1">Main</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for r <- section.casing.rows do %>
                            <tr>
                              <td class="border px-2 py-1 font-medium">{r.field}</td>
                              <td class="border px-2 py-1 text-center">{r.surface}</td>
                              <%= if has_int do %>
                                <td class="border px-2 py-1 text-center">{r.intermediate}</td>
                              <% end %>
                              <td class="border px-2 py-1 text-center">{r.main}</td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% :geo_formations -> %>
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
                          <%= for f <- section.rows do %>
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
                    <% :drilling_fluids -> %>
                      <table class="w-full text-sm mt-2 border-collapse">
                        <thead>
                          <tr class="bg-gray-100">
                            <th class="border px-2 py-1">Hole Section</th>
                            <th class="border px-2 py-1">Hole Size (mm)</th>
                            <th class="border px-2 py-1">Interval (mKB)</th>
                            <th class="border px-2 py-1">System Type</th>
                            <th class="border px-2 py-1">Density (kg/m³)</th>
                            <th class="border px-2 py-1">Viscosity (s/L)</th>
                            <th class="border px-2 py-1">Fluid Loss (mL/30min)</th>
                            <th class="border px-2 py-1">pH</th>
                            <th class="border px-2 py-1">Comments</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for r <- section.rows do %>
                            <tr>
                              <td class="border px-2 py-1">{r.hole_section}</td>
                              <td class="border px-2 py-1">{r.hole_size_mm}</td>
                              <td class="border px-2 py-1">{r.interval_mkb}</td>
                              <td class="border px-2 py-1">{r.system_type}</td>
                              <td class="border px-2 py-1">{r.density_kg_m3}</td>
                              <td class="border px-2 py-1">{r.viscosity_s_l}</td>
                              <td class="border px-2 py-1">{r.fluid_loss_ml}</td>
                              <td class="border px-2 py-1">{r.ph}</td>
                              <td class="border px-2 py-1">{r.comments}</td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% :logging -> %>
                      <% cols = section.columns
                      max_len = [cols.tool_types, cols.runs] |> Enum.map(&length/1) |> Enum.max()
                      pad = fn list -> list ++ List.duplicate("", max_len - length(list)) end
                      rows = Enum.zip([pad.(cols.tool_types), pad.(cols.runs)]) %>
                      <table class="w-full text-sm mt-2 border-collapse">
                        <thead>
                          <tr class="bg-gray-100">
                            <th class="border px-2 py-1 text-left">Tool Type</th>
                            <th class="border px-2 py-1 text-left">Run in Well</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for {tool, run} <- rows do %>
                            <tr>
                              <td class="border px-2 py-1">{tool}</td>
                              <td class="border px-2 py-1">{run}</td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                      <%= if cols.notes != "" do %>
                        <pre class="text-xs whitespace-pre-wrap text-left mt-2 text-gray-600 border-l-2 border-gray-300 pl-2"><%= cols.notes %></pre>
                      <% end %>
                    <% :raw -> %>
                      <pre class="text-xs whitespace-pre-wrap text-left"><%= section.raw_text %></pre>
                  <% end %>
                </div>
              <% end %>
              <div class="mt-4">
                <button
                  type="submit"
                  class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition"
                >
                  Generate Excel Files
                </button>
              </div>
            </div>
          <% end %>
        </form>
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
