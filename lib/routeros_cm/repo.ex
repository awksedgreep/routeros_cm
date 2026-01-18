defmodule RouterosCm.Repo do
  use Ecto.Repo,
    otp_app: :routeros_cm,
    adapter: Ecto.Adapters.Postgres
end
