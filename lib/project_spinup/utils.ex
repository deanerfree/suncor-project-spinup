defmodule ProjectSpinup.Utils do
  require Logger
  @moduledoc """
  Utility functions for the ProjectSpinup application.
  """
  @spec valid_pdf_request?(any()) :: boolean()
  @doc """
  Validates if the incoming request is a valid PDF request.
  This is a placeholder function and should be expanded with actual validation logic in the future.
  """
  def valid_pdf_request?(request) do
    # Placeholder validation logic for PDF request
    # In a real implementation, this would check the structure of the request and ensure it contains a valid PDF file
    is_map(request) and Map.has_key?(request, :file_path) and Map.has_key?(request, :client_name) and String.ends_with?(request.client_name, ".pdf")
  end

  @doc """
  Processes a PDF file.

  Takes a file path and returns the processed result or an error.

  ## Examples

      iex> ProjectSpinup.Utils.process_pdf("/path/to/file.pdf")
      {:ok, result}

      iex> ProjectSpinup.Utils.process_pdf("/invalid/path.pdf")
      {:error, reason}
  """
  def process_pdf(file_path, client_name) when is_binary(file_path) and is_binary(client_name) do
    cond do
      not File.exists?(file_path) ->
        {:error, "File not found: #{file_path}"}

      not String.ends_with?(client_name, ".pdf") ->
        Logger.warning("Invalid file type: #{client_name}")
        {:error, "File is not a PDF"}

      true ->
        # TODO: Implement PDF processing logic
        Logger.info("Processing PDF file: #{file_path} for client: #{client_name}")
        {:ok, text} = parse_pdf(file_path)
        Logger.info(text)
        {:ok, %{file_path: file_path, client_name: client_name, processed_at: DateTime.utc_now()}}
    end
  end

  def parse_pdf(file_path) when is_binary(file_path) do
    # Placeholder for PDF parsing logic
    # In a real implementation, this would extract relevant information from the PDF file and return it in a structured format
    Logger.info("Parsing PDF file: #{file_path}")
    {xml, 0} = System.cmd("pdftohtml", ["-xml", "-stdout", "-noframes", file_path],
                          stderr_to_stdout: true)
    Logger.info("Extracted text: #{xml}")
    {:ok, %{text: xml}}
  end
end
