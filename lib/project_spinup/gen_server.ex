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

  @spec handle_incoming_pdf_request(any()) :: :ok
  @doc """
    Handles incoming PDF request from the frontend.
    First we check for a valid request with a pdf file, then we process the PDF request and return a response.
    - If the request is pdf file is valid, we can process the PDF request and return a response. If the request is invalid, we can return an error response.
    - If the request is not a pdf file, we can return an error response. If the request is valid, we can process the PDF request and return a response.
  """
  def handle_incoming_pdf_request(request) do
    Logger.info("Received PDF request: #{inspect(request)}")
    # Check if the request is a valid PDF filerec
    if Utils.valid_pdf_request?(request) do
      # Process the PDF request and return a response
      WellStickParser.parse(request.file_path)
      # IO.inspect(stick_data, label: "Parsed stick data")

    else
      # Return an error response for invalid PDF request
      Logger.error("Invalid PDF request: ")
      Logger.error(inspect(request))
      {:error, :invalid_pdf_request}
    end
  end
end
