defmodule FirehoseSimulatorWeb.SimulationPlanComponents do
  @moduledoc false

  use Phoenix.Component

  attr :simulation_plan, :map, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  def simulation_plan_summary(assigns) do
    assigns =
      assigns
      |> assign(:posts_count, section_count(assigns.simulation_plan.posts))
      |> assign(:sessions_count, section_count(assigns.simulation_plan.sessions))
      |> assign(:follows_count, section_count(assigns.simulation_plan.follows))

    ~H"""
    <p id={@id} class={@class}>
      posts: {@posts_count} | sessions: {@sessions_count} | follows: {@follows_count}
    </p>
    """
  end

  defp section_count(nil), do: 0
  defp section_count(events) when is_list(events), do: length(events)
end
