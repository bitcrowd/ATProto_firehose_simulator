defmodule FirehoseSimulatorWeb.PageHTML do
  @moduledoc """
  HEEx templates for the minimal landing pages served by the web app.
  """
  use FirehoseSimulatorWeb, :html

  embed_templates "page_html/*"
end
