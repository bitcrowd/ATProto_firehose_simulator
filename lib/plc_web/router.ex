# https://github.com/did-method-plc/did-method-plc/blob/main/packages/server/src/routes.ts
defmodule PLCWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/" do
    pipe_through(:api)
    get("/:did/data", PLCWeb.Controller, :data)
    get("/:did/log", PLCWeb.Controller, :full_log)
    get("/:did/log/last", PLCWeb.Controller, :log)
    get("/:did", PLCWeb.Controller, :show)
    post("/:did", PLCWeb.Controller, :create)
  end
end
