defmodule ProjectSpinupWeb.ReviewLive do
  @moduledoc """
    LiveView to display the results of the PDF parsing and template population. This will be the final step in the project spinup process where the user can review the extracted data and download the populated templates.
  """
  use ProjectSpinupWeb, :live_view
  alias ProjectSpinup.GenServer
  alias ProjectSpinupWeb.Layouts

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
        "afe",
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

  defp infer_afe(result) do
    names = result |> Enum.map(& &1.well_name) |> Enum.join(" ")

    cond do
      String.contains?(names, "Firebag") -> "SUENTQ00165983"
      String.contains?(names, "LS") or String.contains?(names, "Lightspeed") -> "SUENTQ00166572"
      true -> ""
    end
  end

  defp section_icon("Surface Location Information"), do: "hero-map-pin"
  defp section_icon("Geological Formation Information"), do: "hero-beaker"
  defp section_icon("Drill Cutting / Coring Information"), do: "hero-wrench-screwdriver"
  defp section_icon("Drilling Fluids"), do: "hero-funnel"
  defp section_icon("Drilling Notes"), do: "hero-document-text"
  defp section_icon("Casing Design"), do: "hero-circle-stack"
  defp section_icon("Logging Information"), do: "hero-table-cells"
  defp section_icon("General Information"), do: "hero-information-circle"
  defp section_icon("Piezometer Design"), do: "hero-presentation-chart-line"
  defp section_icon("Thermocouple Design"), do: "hero-bolt"
  defp section_icon("Cementing"), do: "hero-rectangle-stack"
  defp section_icon("Casing Accessories"), do: "hero-wrench"
  defp section_icon(_), do: "hero-document"

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
    <Layouts.workflow_header current_step={:review} />
    <div id="well-storage" phx-hook="LocalStorageHook" data-key="well_stick"></div>
    <div class="max-w-5xl mx-auto w-full px-4 pb-8">
      <%= if @result do %>
        <%= for page <- @result do %>
          <div class="mb-6">
            <h1 class="text-3xl font-bold flex items-center gap-2">
              {page.well_name}
            </h1>
            <div class="flex flex-wrap gap-2 mt-2">
              <span class="badge badge-outline">UWI: {page.uwi}</span>
              <span class="badge badge-outline">Well ID: {page.well_id}</span>
              <span class="badge badge-outline">Licence: {page.licence}</span>
            </div>
          </div>
        <% end %>

        <div class="mb-6">
          <p class="text-base-content/70 mb-2">Review the data extracted from the uploaded PDF.</p>
          <ol class="list-decimal list-inside text-sm text-base-content/60 space-y-1">
            <li>
              If you see any issues, make the necessary corrections before generating the files.
            </li>
            <li>
              Once satisfied, click
              <span class="font-semibold text-base-content">Generate Excel Files</span>
              to download the populated templates.
            </li>
          </ol>
        </div>

        <form phx-submit="generate_excel_files" class="flex flex-col gap-6">
          <div
            id="rig-details"
            phx-hook="LocalStorageHook"
            data-key="rig_details"
            class="card bg-base-200 shadow-sm"
          >
            <div class="card-body gap-4">
              <h2 class="card-title">
                <.icon name="hero-wrench-screwdriver" class="size-5 text-primary" /> Rig Details
              </h2>
              <div class="gap-4 grid grid-cols-2">
                <.input type="text" name="rig_name" label="Rig Name" value="" />
                <.input type="date" name="spud_date" label="Spud Date" value="" />
                <.input
                  type="select"
                  name="afe"
                  label="AFE"
                  value={infer_afe(@result)}
                  options={[
                    {"SUENTQ00166572 (Lightspeed / LS)", "SUENTQ00166572"},
                    {"SUENTQ00165983 (Firebag)", "SUENTQ00165983"}
                  ]}
                />
                <div class="col-span-2 flex flex-col gap-4 text-left border border-base-300 rounded-lg p-4">
                  <h3 class="font-semibold flex items-center gap-2">
                    <.icon name="hero-identification" class="size-4 text-primary" />
                    Geology Contact Information
                  </h3>
                  <h4 class="font-medium text-sm text-base-content/70">Office Geologist</h4>
                  <div class="flex text-left w-full gap-4">
                    <div class="text-left w-1/2">
                      <.input type="text" name="og" label="Office Geologist" value="" />
                      <.phone_input id="og-ph" name="og_ph" label="Phone Number" />
                    </div>
                  </div>
                  <h4 class="font-medium text-sm text-base-content/70">Wellsite Geology Team</h4>
                  <div class="flex text-left w-full gap-4">
                    <div class="text-left w-1/2">
                      <.input type="text" name="geo_day" label="Geologist Days" value="" />
                      <.phone_input
                        id="geo-day-ph"
                        name="geo_day_ph"
                        label="Geologist Days Phone Number"
                      />
                    </div>
                    <div class="text-left w-1/2">
                      <.input type="text" name="geo_night" label="Geologist Night" value="" />
                      <.phone_input
                        id="geo-night-ph"
                        name="geo_night_ph"
                        label="Geologist Nights Phone Number"
                      />
                    </div>
                  </div>
                </div>
                <div class="col-span-2 flex flex-col gap-4 text-left border border-base-300 rounded-lg p-4">
                  <h3 class="font-semibold flex items-center gap-2">
                    <.icon name="hero-identification" class="size-4 text-primary" />
                    Well Site Supervisors
                  </h3>
                  <div class="flex gap-4">
                    <div class="text-left w-1/2">
                      <.input type="text" name="wss_day" label="WSS Days" value="" />
                    </div>
                    <div class="text-left w-1/2">
                      <.input type="text" name="wss_night" label="WSS Night" value="" />
                    </div>
                  </div>
                  <div class="w-1/2">
                    <.phone_input id="rig-ph" name="rig_ph" label="Rig Phone Number" />
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%= for page <- @result do %>
            <div class="card bg-base-200 shadow-sm">
              <div class="card-body gap-4">
                <h2 class="card-title">
                  <.icon name="hero-document-magnifying-glass" class="size-5 text-primary" />
                  Parsed Data
                </h2>

                <div class="divide-y divide-base-300">
                  <%= for {section_name, section} <- ordered_sections(page.sections), section != nil do %>
                    <div class="py-4">
                      <h3 class="font-semibold flex items-center gap-2 mb-3">
                        <.icon name={section_icon(section_name)} class="size-4 text-primary" />
                        {section_name}
                      </h3>

                      <%= case section_type(section) do %>
                        <% :location -> %>
                          <div class="flex flex-wrap gap-8 text-sm">
                            <table class="border-collapse">
                              <tbody>
                                <tr>
                                  <td class="pr-4 py-0.5 text-base-content/60">
                                    Ground Level (masl)
                                  </td>
                                  <td class="border-b border-base-300 px-2 py-0.5 font-mono">
                                    {section.location.elevation.ground_level_masl}
                                  </td>
                                </tr>
                                <tr>
                                  <td class="pr-4 py-0.5 text-base-content/60">
                                    KB - Ground Level (m)
                                  </td>
                                  <td class="border-b border-base-300 px-2 py-0.5 font-mono">
                                    {section.location.elevation.kb_ground_level_m}
                                  </td>
                                </tr>
                                <tr>
                                  <td class="pr-4 py-0.5 text-base-content/60">KB Elevation (mSS)</td>
                                  <td class="border-b border-base-300 px-2 py-0.5 font-mono">
                                    {section.location.elevation.kb_elevation_mss}
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                            <table class="border-collapse">
                              <thead>
                                <tr>
                                  <th
                                    colspan="2"
                                    class="text-left text-base-content/60 font-normal pb-1"
                                  >
                                    {section.location.coordinates.system}
                                  </th>
                                </tr>
                              </thead>
                              <tbody>
                                <tr>
                                  <td class="pr-4 py-0.5 text-base-content/60">Northing</td>
                                  <td class="border-b border-base-300 px-2 py-0.5 font-mono">
                                    {section.location.coordinates.northing}
                                  </td>
                                </tr>
                                <tr>
                                  <td class="pr-4 py-0.5 text-base-content/60">Easting</td>
                                  <td class="border-b border-base-300 px-2 py-0.5 font-mono">
                                    {section.location.coordinates.easting}
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                          </div>
                        <% :casing -> %>
                          <% has_int = "intermediate" in section.casing.columns %>
                          <div class="overflow-x-auto">
                            <table class="table table-xs table-zebra w-full">
                              <thead>
                                <tr>
                                  <th>Field</th>
                                  <th>Surface</th>
                                  <%= if has_int do %>
                                    <th>Intermediate</th>
                                  <% end %>
                                  <th>Main</th>
                                </tr>
                              </thead>
                              <tbody>
                                <%= for r <- section.casing.rows do %>
                                  <tr>
                                    <td class="font-medium">{r.field}</td>
                                    <td>{r.surface}</td>
                                    <%= if has_int do %>
                                      <td>{r.intermediate}</td>
                                    <% end %>
                                    <td>{r.main}</td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        <% :geo_formations -> %>
                          <div class="overflow-x-auto">
                            <table class="table table-xs table-zebra w-full">
                              <thead>
                                <tr>
                                  <th>Formation</th>
                                  <th>MASL TVD</th>
                                  <th>MKB TVD</th>
                                  <th>Pressure (kPa)</th>
                                  <th>EMW (kg/m³)</th>
                                  <th>Drilling Problems</th>
                                </tr>
                              </thead>
                              <tbody>
                                <%= for f <- section.rows do %>
                                  <tr>
                                    <td>{f.formation}</td>
                                    <td>{f.masl_tvd}</td>
                                    <td>{f.mkb_tvd}</td>
                                    <td>{f.pressure_kpa}</td>
                                    <td>{f.emw_kg_m3}</td>
                                    <td>{f.potential_drilling_problems}</td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        <% :drilling_fluids -> %>
                          <div class="overflow-x-auto">
                            <table class="table table-xs table-zebra w-full">
                              <thead>
                                <tr>
                                  <th>Hole Section</th>
                                  <th>Hole Size (mm)</th>
                                  <th>Interval (mKB)</th>
                                  <th>System Type</th>
                                  <th>Density (kg/m³)</th>
                                  <th>Viscosity (s/L)</th>
                                  <th>Fluid Loss (mL/30min)</th>
                                  <th>pH</th>
                                  <th>Comments</th>
                                </tr>
                              </thead>
                              <tbody>
                                <%= for r <- section.rows do %>
                                  <tr>
                                    <td>{r.hole_section}</td>
                                    <td>{r.hole_size_mm}</td>
                                    <td>{r.interval_mkb}</td>
                                    <td>{r.system_type}</td>
                                    <td>{r.density_kg_m3}</td>
                                    <td>{r.viscosity_s_l}</td>
                                    <td>{r.fluid_loss_ml}</td>
                                    <td>{r.ph}</td>
                                    <td>{r.comments}</td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        <% :logging -> %>
                          <% cols = section.columns
                          max_len = [cols.tool_types, cols.runs] |> Enum.map(&length/1) |> Enum.max()
                          pad = fn list -> list ++ List.duplicate("", max_len - length(list)) end
                          rows = Enum.zip([pad.(cols.tool_types), pad.(cols.runs)]) %>
                          <div class="overflow-x-auto">
                            <table class="table table-xs table-zebra w-full">
                              <thead>
                                <tr>
                                  <th>Tool Type</th>
                                  <th>Run in Well</th>
                                </tr>
                              </thead>
                              <tbody>
                                <%= for {tool, run} <- rows do %>
                                  <tr>
                                    <td>{tool}</td>
                                    <td>{run}</td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                          <%= if cols.notes != "" do %>
                            <p class="text-xs mt-2 text-base-content/60 border-l-2 border-base-300 pl-3 whitespace-pre-wrap">
                              {cols.notes}
                            </p>
                          <% end %>
                        <% :raw -> %>
                          <% lines =
                            section.raw_text
                            |> String.split("\n")
                            |> Enum.map(&String.trim/1)
                            |> Enum.reject(&(&1 == ""))
                            |> Enum.reject(&(String.downcase(&1) == String.downcase(section_name))) %>
                          <%= if length(lines) > 1 do %>
                            <ul class="list-disc list-inside text-sm space-y-1 text-base-content/80">
                              <%= for line <- lines do %>
                                <li>{line}</li>
                              <% end %>
                            </ul>
                          <% else %>
                            <p class="text-sm text-base-content/80">{section.raw_text}</p>
                          <% end %>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <div class="card-actions justify-end pt-2">
                  <button type="submit" class="btn btn-success">
                    <.icon name="hero-arrow-down-tray" class="size-5" /> Generate Excel Files
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </form>
      <% else %>
        <div class="card bg-base-200 shadow-sm mt-8">
          <div class="card-body items-center text-center gap-3">
            <.icon name="hero-document-magnifying-glass" class="size-12 text-base-content/30" />
            <h2 class="card-title">No results to display</h2>
            <p class="text-base-content/60">Please upload a PDF to see the extracted well data.</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
