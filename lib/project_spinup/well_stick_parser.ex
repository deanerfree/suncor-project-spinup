defmodule ProjectSpinup.WellStickParser do
  @moduledoc """
  Parses Suncor well stick diagram PDFs and extracts named sections using
  a Python/pdfplumber subprocess.

  ## Usage

      # Extract specific sections
      {:ok, pages} = ProjectSpinup.WellStickParser.parse("/path/to/well_stick.pdf",
        sections: ["Geological Formation Information", "Drilling Notes"]
      )

      # Extract all known sections (default)
      {:ok, pages} = ProjectSpinup.WellStickParser.parse("/path/to/well_stick.pdf")

  ## Return shape

      [
        %{
          page: 1,
          well_id: "OB301",
          licence: "0521278",
          sections: %{
            "Geological Formation Information" => %{
              raw_text: "Geological Formation Information\\n...",
              formations: [
                %{
                  formation: "Surface Casing",
                  masl_tvd: 489.1,
                  mkb_tvd: 70.7,
                  pressure_kpa: 694.0,
                  emw_kg_m3: 1000.0,
                  potential_drilling_problems: "Loss circ, mud rings"
                },
                ...
              ]
            },
            "Drilling Notes" => %{raw_text: "Drilling Notes\\n●159mm pilot hole..."},
            "Logging Information" => %{raw_text: "Logging Information\\nTool Type..."},
            "Casing Design" => %{raw_text: "Casing Design\\nSurface Main\\n..."}
          }
        }
      ]

  ## Available sections

      "Geological Formation Information"   # structured (formations list) + raw_text
      "Surface Location Information"       # raw_text
      "General Information"                # raw_text
      "Drilling Notes"                     # raw_text
      "Casing Accessories"                 # raw_text
      "Drilling Fluids"                    # raw_text
      "Cementing"                          # raw_text
      "Drill Cutting / Coring Information" # raw_text
      "Casing Design"                      # raw_text
      "Piezometer Design"                  # raw_text
      "Logging Information"                # raw_text + columns (tool_types, runs, notes)
      "Thermocouple Design"                # raw_text

  ## Configuration

      # config/config.exs
      config :project_spinup, ProjectSpinup.WellStickParser,
        script_path: "/path/to/extract_pdf_data.py"

  Defaults to `priv/python/extract_pdf_data.py` relative to the app directory.
  """

  require Logger

  @type formation :: %{
          formation: String.t(),
          masl_tvd: float() | nil,
          mkb_tvd: float() | nil,
          pressure_kpa: float() | nil,
          emw_kg_m3: float() | nil,
          potential_drilling_problems: String.t() | nil
        }

  @type section :: %{
          raw_text: String.t(),
          columns: %{tool_types: [String.t()], runs: [String.t()], notes: [String.t()]} | nil,
          formations: [formation()] | nil
        }

  @type page_result :: %{
          page: pos_integer(),
          well_name: String.t() | nil,
          uwi: String.t() | nil,
          well_id: String.t() | nil,
          licence: String.t() | nil,
          sections: %{String.t() => section() | nil}
        }

  @all_sections [
    "Geological Formation Information",
    "Surface Location Information",
    "General Information",
    "Drilling Notes",
    "Casing Accessories",
    "Drilling Fluids",
    "Cementing",
    "Drill Cutting / Coring Information",
    "Casing Design",
    "Piezometer Design",
    "Logging Information",
    "Thermocouple Design"
  ]

  @spec all_sections() :: [String.t()]
  def all_sections, do: @all_sections

  @spec parse(Path.t(), keyword()) :: {:ok, [page_result()]} | {:error, String.t()}
  def parse(pdf_path, opts \\ []) do
    requested = Keyword.get(opts, :sections, @all_sections)

    with :ok <- validate_pdf_path(pdf_path),
         :ok <- validate_sections(requested),
         script <- script_path(),
         :ok <- validate_script_path(script),
         {:ok, json} <- run_extractor(script, pdf_path, requested),
         {:ok, raw} <- Jason.decode(json),
         :ok <- validate_well_stick(raw) do
      {:ok, Enum.map(raw, &cast_page/1)}
    end
  end

  @spec parse!(Path.t(), keyword()) :: [page_result()]
  def parse!(pdf_path, opts \\ []) do
    case parse(pdf_path, opts) do
      {:ok, pages} -> pages
      {:error, reason} -> raise RuntimeError, message: reason
    end
  end

  @spec verify_dependencies!() :: :ok
  def verify_dependencies! do
    case System.cmd("python3", ["-c", "import pdfplumber"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> raise "pdfplumber not installed. Run: pip install pdfplumber --break-system-packages"
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp validate_well_stick(raw) do
    all_invalid = Enum.all?(raw, fn page -> page["valid"] == false end)

    if all_invalid do
      {:error, "Not a valid well stick diagram — no well data found in the PDF"}
    else
      :ok
    end
  end

  defp run_extractor(script, pdf_path, sections) do
    args = [script, pdf_path | sections]

    case System.cmd("python3", args, stderr_to_stdout: false) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.error("[WellStickParser] Python exited #{code}: #{inspect(output)}")
        {:error, "Extraction failed (exit #{code}): #{String.trim(output)}"}
    end
  end

  defp cast_page(raw) do
    %{
      page:      raw["page"],
      valid:     raw["valid"],
      well_name: raw["well_name"],
      uwi:       raw["uwi"],
      well_id:   raw["well_id"],
      licence:   raw["licence"],
      sections:  cast_sections(raw["sections"] || %{})
    }
  end

  defp cast_sections(raw_sections) do
    Map.new(raw_sections, fn {name, section} -> {name, cast_section(section)} end)
  end

  defp cast_section(nil), do: nil

  defp cast_section(raw) do
    base = %{raw_text: raw["raw_text"]}

    base =
      case raw["formations"] do
        nil        -> base
        formations -> Map.put(base, :formations, Enum.map(formations, &cast_formation/1))
      end

    case raw["columns"] do
      nil     -> base
      columns -> Map.put(base, :columns, cast_logging_columns(columns))
    end
  end

  defp cast_logging_columns(raw) do
    %{
      tool_types: raw["tool_types"] || [],
      runs:       raw["runs"]       || [],
      notes:      raw["notes"]      || []
    }
  end

  defp cast_formation(raw) do
    %{
      formation: raw["formation"],
      masl_tvd: raw["masl_tvd"],
      mkb_tvd: raw["mkb_tvd"],
      pressure_kpa: raw["pressure_kpa"],
      emw_kg_m3: raw["emw_kg_m3"],
      potential_drilling_problems: raw["potential_drilling_problems"]
    }
  end

  defp validate_pdf_path(path) do
    if File.exists?(path),
      do: :ok,
      else: {:error, "PDF not found: #{path}"}
  end

  defp validate_sections(sections) do
    unknown = Enum.reject(sections, &(&1 in @all_sections))

    if unknown == [],
      do: :ok,
      else: {:error, "Unknown section(s): #{inspect(unknown)}. Valid: #{inspect(@all_sections)}"}
  end

  defp validate_script_path(path) do
    if File.exists?(path),
      do: :ok,
      else:
        {:error,
         "Python extractor not found: #{path}. " <>
           "Set :script_path in config or place extract_pdf_data.py in priv/python/."}
  end

  defp script_path do
    :project_spinup
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:script_path, default_script_path())
  end

  defp default_script_path do
    :project_spinup
    |> :code.priv_dir()
    |> Path.join("python/extract_pdf_data.py")
  end
end
