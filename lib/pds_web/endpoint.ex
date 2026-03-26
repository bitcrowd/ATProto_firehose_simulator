defmodule PDSWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :firehose_simulator

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: JSON
  )

  plug(Plug.Logger)
  plug(PDSWeb.Router)
end
