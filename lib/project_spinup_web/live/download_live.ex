defmodule ProjectSpinupWeb.DownloadLive do
  use ProjectSpinupWeb, :live_view

  @max_age 300

  def mount(%{"token" => token}, _session, socket) do
    case Phoenix.Token.verify(ProjectSpinupWeb.Endpoint, "download", token, max_age: @max_age) do
      {:ok, file_paths} when is_list(file_paths) ->
        tokens =
          Enum.map(file_paths, fn path ->
            %{
              label: Path.basename(path),
              token: Phoenix.Token.sign(ProjectSpinupWeb.Endpoint, "download", path),
              size: file_size(path)
            }
          end)

        {:ok, assign(socket, files: tokens, error: nil)}

      {:ok, file_path} when is_binary(file_path) ->
        tokens = [
          %{
            label: Path.basename(file_path),
            token: Phoenix.Token.sign(ProjectSpinupWeb.Endpoint, "download", file_path),
            size: file_size(file_path)
          }
        ]

        {:ok, assign(socket, files: tokens, error: nil)}

      {:error, :expired} ->
        {:ok, assign(socket, files: [], error: "Download link has expired")}

      {:error, _} ->
        {:ok, assign(socket, files: [], error: "Invalid download link")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.workflow_header current_step={:download} />
    <div class="w-full flex flex-col gap-8 text-center p-8">
      <%= if @error do %>
        <div class="flex flex-col items-center gap-4 py-8">
          <svg xmlns="http://www.w3.org/2000/svg" width="200" height="180" viewBox="0 0 200 180">
            <defs>
              <style>
                @keyframes sway { 0%,100%{transform:rotate(-3deg) translateY(0)} 50%{transform:rotate(3deg) translateY(2px)} }
                @keyframes feather1 { 0%{transform:translate(0,0) rotate(0deg);opacity:1} 100%{transform:translate(-18px,22px) rotate(-35deg);opacity:0} }
                @keyframes feather2 { 0%{transform:translate(0,0) rotate(0deg);opacity:1} 100%{transform:translate(14px,28px) rotate(28deg);opacity:0} }
                @keyframes feather3 { 0%{transform:translate(0,0) rotate(0deg);opacity:1} 100%{transform:translate(6px,24px) rotate(-15deg);opacity:0} }
                @keyframes stars { 0%,100%{opacity:0;transform:scale(.6)} 50%{opacity:1;transform:scale(1)} }
                .bird-body { animation: sway 4s ease-in-out infinite; transform-origin: 100px 110px; }
                .f1 { animation: feather1 3s ease-in infinite 1s; transform-origin: 88px 108px; }
                .f2 { animation: feather2 3s ease-in infinite 1.4s; transform-origin: 96px 112px; }
                .f3 { animation: feather3 3s ease-in infinite 1.8s; transform-origin: 104px 106px; }
                .star1 { animation: stars 2s ease-in-out infinite 0s; transform-origin: 60px 62px; }
                .star2 { animation: stars 2s ease-in-out infinite .35s; transform-origin: 50px 50px; }
                .star3 { animation: stars 2s ease-in-out infinite .7s; transform-origin: 68px 50px; }
              </style>
            </defs>
            <!-- floating feathers -->
            <ellipse class="f1" cx="88" cy="108" rx="5" ry="2" fill="#5B9BD5" opacity=".5" transform="rotate(-20,88,108)"/>
            <ellipse class="f2" cx="96" cy="112" rx="4" ry="1.8" fill="#5B9BD5" opacity=".45" transform="rotate(10,96,112)"/>
            <ellipse class="f3" cx="104" cy="106" rx="4.5" ry="1.8" fill="#5B9BD5" opacity=".4" transform="rotate(-5,104,106)"/>
            <g class="bird-body">
              <!-- branch -->
              <rect x="30" y="128" width="140" height="6" rx="3" fill="#7A6248" opacity=".45"/>
              <rect x="28" y="130" width="6" height="40" rx="3" fill="#7A6248" opacity=".3"/>
              <rect x="166" y="130" width="6" height="40" rx="3" fill="#7A6248" opacity=".3"/>
              <!-- tail -->
              <ellipse cx="138" cy="118" rx="18" ry="8" fill="#2B6CB0" opacity=".85" transform="rotate(20,138,118)"/>
              <!-- wing -->
              <ellipse cx="100" cy="116" rx="26" ry="10" fill="#3B82C4" opacity=".7" transform="rotate(15,100,116)"/>
              <!-- body -->
              <ellipse cx="95" cy="108" rx="28" ry="22" fill="#4A90D9"/>
              <!-- breast -->
              <ellipse cx="92" cy="113" rx="15" ry="13" fill="#E8742A"/>
              <!-- head -->
              <circle cx="70" cy="86" r="18" fill="#3B7EC8"/>
              <!-- beak -->
              <polygon points="58,92 50,101 62,98" fill="#F5C518"/>
              <polygon points="58,90 52,97 62,95" fill="#F0B800" opacity=".7"/>
              <!-- X eyes -->
              <line x1="62" y1="79" x2="68" y2="85" stroke="#E53E3E" stroke-width="2.5" stroke-linecap="round"/>
              <line x1="68" y1="79" x2="62" y2="85" stroke="#E53E3E" stroke-width="2.5" stroke-linecap="round"/>
              <!-- legs -->
              <line x1="90" y1="128" x2="86" y2="141" stroke="#C8960A" stroke-width="2.5" stroke-linecap="round"/>
              <line x1="86" y1="141" x2="80" y2="147" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
              <line x1="86" y1="141" x2="84" y2="149" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
              <line x1="86" y1="141" x2="92" y2="149" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
              <line x1="106" y1="128" x2="110" y2="141" stroke="#C8960A" stroke-width="2.5" stroke-linecap="round"/>
              <line x1="110" y1="141" x2="116" y2="147" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
              <line x1="110" y1="141" x2="112" y2="149" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
              <line x1="110" y1="141" x2="104" y2="149" stroke="#C8960A" stroke-width="2" stroke-linecap="round"/>
            </g>
            <!-- daze stars -->
            <g class="star1"><text font-size="13" text-anchor="middle" x="60" y="66" opacity=".8" fill="#F5C518">✦</text></g>
            <g class="star2"><text font-size="10" text-anchor="middle" x="50" y="54" opacity=".7" fill="#F5C518">✦</text></g>
            <g class="star3"><text font-size="9" text-anchor="middle" x="72" y="52" opacity=".6" fill="#F5C518">✦</text></g>
          </svg>
          <h2 class="text-2xl font-bold text-base-content/70">Link Expired</h2>
          <p class="text-base-content/50">{@error}</p>
          <p class="text-sm text-base-content/40">Download links are only valid for 5 minutes. Please generate a new link.</p>
        </div>
      <% else %>
        <div class="w-full flex flex-col gap-4 text-lg font-medium">
          <h1 class="text-3xl font-bold mb-4">Your Downloads are Ready</h1>
          <p class="font-medium">Thank you for using the Project Spinup Tool.</p>
          <p>Your files are ready. Click the buttons below to download your reports.</p>
          <p>Note: These links will expire in 5 minutes.</p>
          <div class="flex flex-col gap-2 items-center mt-4 w-full max-w-lg mx-auto">
            <%= for file <- @files do %>
              <a
                href={"/download/file?token=#{file.token}"}
                download
                class="flex items-center gap-4 w-full px-4 py-3 rounded-lg border border-base-300 bg-base-100 hover:bg-base-200 transition-colors group"
              >
                <span class="shrink-0 text-green-600">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" class="w-8 h-8">
                    <path fill="#169154" d="M29,6H15.744C14.781,6,14,6.781,14,7.744v7.259h15V6z" />
                    <path fill="#18482a" d="M14,15.003h15V22h-15V15.003z" />
                    <path fill="#169154" d="M14,22h15v7H14V22z" />
                    <path fill="#18482a" d="M14,29h15v7.256C29,37.219,28.219,38,27.256,38H14V29z" />
                    <path fill="#29c27f" d="M42.256,6H29v9h13V7.744C42,6.781,41.219,6,42.256,6z" />
                    <path fill="#27663f" d="M29,15.003h13V22H29V15.003z" />
                    <path fill="#29c27f" d="M29,22h13v7H29V22z" />
                    <path fill="#27663f" d="M29,29h13v7.256C42,37.219,41.219,38,42.256,38H29V29z" />
                    <path
                      fill="#0c7238"
                      d="M6,42H26c1.105,0,2-0.895,2-2V28H4v12C4,41.105,4.895,42,6,42z"
                    />
                    <path
                      fill="#fff"
                      d="M9.962,37l-1.977-3.754L5.995,37H4l2.985-4.56L4.085,28h1.995l1.93,3.695L9.934,28h1.992l-2.947,4.352L12,37H9.962z"
                    />
                  </svg>
                </span>
                <div class="flex flex-col flex-1 text-left min-w-0">
                  <span class="text-sm font-medium truncate">{file.label}</span>
                  <span class="text-sm opacity-60">{file.size}</span>
                </div>
                <span class="shrink-0 opacity-50 group-hover:opacity-100 transition-opacity">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="w-5 h-5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                    stroke-width="2"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                    />
                  </svg>
                </span>
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size >= 1_048_576 ->
        "#{Float.round(size / 1_048_576, 1)} MB"

      {:ok, %{size: size}} when size >= 1_024 ->
        "#{Float.round(size / 1_024, 1)} KB"

      {:ok, %{size: size}} ->
        "#{size} B"

      _ ->
        ""
    end
  end
end
