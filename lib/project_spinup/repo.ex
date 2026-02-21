defmodule ProjectSpinup.Repo do
  use Ecto.Repo,
    otp_app: :project_spinup,
    adapter: Ecto.Adapters.Postgres
end
