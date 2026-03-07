defmodule ProjectSpinupWeb.StepComponents do
  @moduledoc """
    This module will assist on determining which component to render for each step in the project spinup process.
    - 1st step will be the pdf upload
    - 2nd step will display the parsed pdf data and allow the user to confirm or edit the parsed data before proceeding to the next step
    - Final step will be the final step showing the user that the process is complete and a link to download the updated excel templates

    The excel templates includes:
    - A template for the AM report
    - A template for the Sample Descriptions
    - A template for the EOW report
  """
  use ProjectSpinupWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-4">
      <h2 class="text-2xl font-semibold">{@title}</h2>
      {live_render(@socket, @component, id: @id)}
    </div>
    """
  end
end
