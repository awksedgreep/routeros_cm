defmodule RouterosCm.Repo do
  use Ecto.Repo,
    otp_app: :routeros_cm,
    adapter: Ecto.Adapters.SQLite3
end
