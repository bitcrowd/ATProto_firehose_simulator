defmodule PDSWeb.Router do
  use Phoenix.Router

  scope "/" do
    match(:*, "/*path", PDSWeb.Controller, :handle)
  end
end
