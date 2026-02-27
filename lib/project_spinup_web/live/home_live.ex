defmodule ProjectSpinupWeb.HomeLive do
  use ProjectSpinupWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="w-screen h-screen flex items-center justify-center">
      <div class="flex flex-col gap-8 text-center">
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
        <div
          id="drop-zone"
          phx-hook="DragNDropHook"
          phx-update="ignore"
          class="space-y-4 space-x-4 border-4 border-dashed border-gray-300 rounded-lg p-12"
        >
          <div id="file-list" class="flex flex-col items-start gap-2">
            <!-- Dynamically populated list of uploaded files will go here -->
          </div>
          <p>Drop in your stick diagram here</p>
          <input type="file" id="file-input" class="hidden" accept=".pdf" />
          <button class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition">
            Upload Files
          </button>
        </div>
      </div>
    </div>
    """
  end
end
