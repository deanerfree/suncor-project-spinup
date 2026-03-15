defmodule ProjectSpinup.GenServer do
  @moduledoc """
  A GenServer to handle pdf requests are sent to the server. This is a placeholder for now and will be expanded in the future.
  """
  alias ProjectSpinup.Utils
  alias ProjectSpinup.WellStickParser

  use GenServer

  require Logger

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec submit_pdf(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def submit_pdf(request) do
    GenServer.call(__MODULE__, {:pdf_request, request})
  end

  @spec populate_template([map()]) :: {:ok, map()} | {:error, atom() | String.t()}
  def populate_template(request) do
    GenServer.call(__MODULE__, {:populate_template, request})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("#{__MODULE__} started with opts: #{inspect(opts)}")
    {:ok, opts}
  end

  @impl true
  def handle_call({:pdf_request, request}, _from, state) do
    result = handle_incoming_pdf_request(request)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:populate_template, request}, _from, state) do
    Logger.info("Received template population request")

    result =
      try do
        run_build_excel(request)
      rescue
        e ->
          Logger.error("[GenServer] run_build_excel raised: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}")
          {:error, "Excel generation failed: #{Exception.message(e)}"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(msg, _from, state) do
    Logger.warning("#{__MODULE__} received unhandled call: #{inspect(msg)}")
    {:reply, {:error, :unhandled}, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("#{__MODULE__} received unhandled cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("#{__MODULE__} received unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end

  @spec run_build_excel([map()]) :: {:ok, map()} | {:error, String.t()}
  defp run_build_excel(pages) do
    page = Enum.find(pages, List.first(pages), & &1[:valid] != false)

    if is_nil(page) do
      {:error, "No valid pages in request"}
    else
      script =
        :project_spinup
        |> :code.priv_dir()
        |> Path.join("python/build_excel.py")

      output_dir = System.tmp_dir!()

      rig_details = page[:rig_details] || %{}

      case Jason.encode(Map.merge(rig_details, %{
        "well_name" => page[:well_name] || "",
        "uwi" => page[:uwi] || "",
        "licence" => page[:licence] || "",
        "sections" => page[:sections] || %{},
        "output_dir" => output_dir
      })) do
        {:error, reason} ->
          Logger.error("[GenServer] Failed to encode payload: #{inspect(reason)}")
          {:error, "Failed to encode request data: #{inspect(reason)}"}

        {:ok, payload} ->
          case System.cmd("python3", [script, payload], stderr_to_stdout: false) do
            {output, 0} -> parse_excel_output(output)
            {output, code} ->
              Logger.error("[GenServer] build_excel.py exited #{code}: #{inspect(output)}")
              {:error, "Excel generation failed (exit #{code}): #{String.trim(output)}"}
          end
      end
    end
  end

  defp parse_excel_output(output) do
    case Jason.decode(output) do
      {:ok, %{"status" => "ok", "files" => files}} when is_list(files) ->
        {:ok, %{file_paths: files}}

      {:ok, result} ->
        {:error, "Unexpected response: #{inspect(result)}"}

      {:error, _} ->
        {:error, "Failed to parse script output: #{String.trim(output)}"}
    end
  end

  @spec handle_incoming_pdf_request(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  @doc """
    Handles incoming PDF request from the frontend.
    First we check for a valid request with a pdf file, then we process the PDF request and return a response.
    - If the request is pdf file is valid, we can process the PDF request and return a response. If the request is invalid, we can return an error response.
    - If the request is not a pdf file, we can return an error response. If the request is valid, we can process the PDF request and return a response.
  """
  def handle_incoming_pdf_request(request) do
    Logger.info("Received PDF request: #{inspect(request)}")

    if Utils.valid_pdf_request?(request) do
      stick_data = WellStickParser.parse(request.file_path)
      # IO.inspect(stick_data, label: "Parsed stick data")
      stick_data
    else
      Logger.error("Invalid PDF request: #{inspect(request)}")
      {:error, :invalid_pdf_request}
    end
  end
end
