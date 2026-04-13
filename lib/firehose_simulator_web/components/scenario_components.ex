defmodule FirehoseSimulatorWeb.ScenarioComponents do
  @moduledoc false

  use Phoenix.Component

  attr :scenario, :map, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  def scenario_summary(assigns) do
    assigns =
      assigns
      |> assign(:posts_count, section_count(assigns.scenario.posts))
      |> assign(:sessions_count, section_count(assigns.scenario.sessions))
      |> assign(:follows_count, section_count(assigns.scenario.follows))

    ~H"""
    <p id={@id} class={@class}>
      posts: {@posts_count} | sessions: {@sessions_count} | follows: {@follows_count}
    </p>
    """
  end

  defp section_count(nil), do: 0
  defp section_count(events) when is_list(events), do: length(events)
end
