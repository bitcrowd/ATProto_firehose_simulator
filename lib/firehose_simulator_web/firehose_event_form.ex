defmodule FirehoseSimulatorWeb.FirehoseEventForm do
  alias FirehoseSimulator.Firehose.Events.Follow
  alias FirehoseSimulator.Firehose.Events.Post

  @follow_type Follow.type()
  @post_type Post.type()

  def form(params \\ %{}) do
    params
    |> stringify_keys()
    |> changeset()
    |> Map.put(:action, nil)
    |> form_from_changeset()
  end

  def form_from_changeset(changeset) do
    opts =
      [as: :event_config, errors: changeset.errors]
      |> maybe_add_action(changeset.action)

    changeset
    |> form_params()
    |> Phoenix.Component.to_form(opts)
  end

  def validate(params) do
    params
    |> stringify_keys()
    |> changeset()
    |> Map.put(:action, :insert)
    |> case do
      changeset when changeset.valid? ->
        event_attrs(changeset)

      changeset ->
        {:error, changeset}
    end
  end

  def follow?(form), do: Phoenix.HTML.Form.input_value(form, :type) == @follow_type
  def post?(form), do: Phoenix.HTML.Form.input_value(form, :type) == @post_type

  def manual?(form) do
    Phoenix.HTML.Form.input_value(form, :random) not in [true, "true", "on"]
  end

  def type_options, do: [{@follow_type, @follow_type}, {@post_type, @post_type}]

  defp form_params(%Ecto.Changeset{params: params}) when is_map(params), do: params

  defp form_params(%Ecto.Changeset{data: data}) do
    data
    |> Map.from_struct()
    |> Map.take([:type, :random, :author_did, :subject_did, :text])
    |> stringify_keys()
  end

  defp changeset(%{"type" => @post_type} = params), do: Post.changeset(%Post{}, params)

  defp changeset(params),
    do: Follow.changeset(%Follow{}, Map.put_new(params, "type", @follow_type))

  defp event_attrs(%Ecto.Changeset{data: %Post{}} = changeset), do: Post.to_event_attrs(changeset)

  defp event_attrs(%Ecto.Changeset{data: %Follow{}} = changeset),
    do: Follow.to_event_attrs(changeset)

  defp maybe_add_action(opts, nil), do: opts
  defp maybe_add_action(opts, action), do: Keyword.put(opts, :action, action)

  defp stringify_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
