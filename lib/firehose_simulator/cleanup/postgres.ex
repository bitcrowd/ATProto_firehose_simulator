defmodule FirehoseSimulator.Cleanup.Postgres do
  @moduledoc """
  Cleanup runner for simulator-owned data in external Postgres databases.
  """

  alias FirehoseSimulator.Cleanup.Repo
  alias FirehoseSimulator.Data

  @type cleanup_report :: %{
          database_product: String.t(),
          matched_rules: [map()],
          skipped_rules: [map()],
          unknown_tables: [String.t()],
          preview_counts: %{optional(String.t()) => non_neg_integer()},
          deleted_counts: %{optional(String.t()) => non_neg_integer()},
          warnings: [String.t()]
        }

  def preview(database_url) when is_binary(database_url) do
    with_repo(database_url, fn ->
      metadata = fetch_table_metadata()
      rules = compile_rules(metadata)

      preview_counts =
        Map.new(rules, fn rule ->
          {rule_key(rule), count_matches(rule)}
        end)

      %{
        database_product: "postgres",
        matched_rules: Enum.map(rules, &rule_summary(&1, preview_counts[rule_key(&1)])),
        skipped_rules: skipped_rules(rules),
        unknown_tables: [],
        preview_counts: preview_counts,
        deleted_counts: %{},
        warnings: warnings(rules, preview_counts)
      }
    end)
  end

  def execute(database_url) when is_binary(database_url) do
    with_repo(database_url, fn ->
      metadata = fetch_table_metadata()
      rules = compile_rules(metadata)

      preview_counts =
        Map.new(rules, fn rule ->
          {rule_key(rule), count_matches(rule)}
        end)

      deleted_counts =
        Repo.transaction(fn ->
          Enum.reduce(rules, %{}, fn rule, acc ->
            expected = preview_counts[rule_key(rule)]
            deleted = delete_matches(rule)

            if deleted != expected do
              Repo.rollback({:delete_count_mismatch, rule_key(rule), expected, deleted})
            else
              Map.put(acc, rule_key(rule), deleted)
            end
          end)
        end)
        |> case do
          {:ok, counts} ->
            counts

          {:error, {:delete_count_mismatch, rule_key, expected, deleted}} ->
            raise ArgumentError,
                  "cleanup aborted for #{rule_key}: preview=#{expected} delete=#{deleted}"
        end

      %{
        database_product: "postgres",
        matched_rules: Enum.map(rules, &rule_summary(&1, preview_counts[rule_key(&1)])),
        skipped_rules: skipped_rules(rules),
        unknown_tables: [],
        preview_counts: preview_counts,
        deleted_counts: deleted_counts,
        warnings: warnings(rules, preview_counts)
      }
    end)
  end

  def compile_rules(metadata) when is_list(metadata) do
    metadata
    |> Enum.group_by(&{&1.schema, &1.table})
    |> Enum.flat_map(fn {{schema, table}, columns} ->
      table_columns = MapSet.new(columns, & &1.column)

      Data.cleanup_rules()
      |> Enum.flat_map(fn rule ->
        rule.columns
        |> Enum.filter(&MapSet.member?(table_columns, &1))
        |> Enum.map(fn column ->
          %{
            id: rule.id,
            description: rule.description,
            priority: rule.priority,
            schema: schema,
            table: table,
            column: column,
            match: rule.match
          }
        end)
      end)
    end)
    |> Enum.sort_by(fn rule -> {rule.priority, rule.schema, rule.table, rule.column} end)
  end

  defp with_repo(database_url, fun) do
    Repo.with_dynamic_repo(
      [
        url: database_url,
        show_sensitive_data_on_connection_error: true,
        stacktrace: true
      ],
      fn ->
        fun.()
      end
    )
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, message} when is_binary(message) ->
        {:error, message}
    end
  rescue
    error in DBConnection.ConnectionError ->
      {:error, Exception.message(error)}

    error in Postgrex.Error ->
      {:error, Exception.message(error)}

    error in ArgumentError ->
      {:error, Exception.message(error)}
  end

  defp fetch_table_metadata do
    sql = """
    select table_schema, table_name, column_name, data_type, udt_name
    from information_schema.columns
    where table_schema not in ('pg_catalog', 'information_schema')
    """

    %{rows: rows} = Repo.query!(sql, [])

    rows
    |> Enum.map(fn [schema, table, column, data_type, udt_name] ->
      %{schema: schema, table: table, column: column, data_type: data_type, udt_name: udt_name}
    end)
    |> Enum.filter(&text_like_column?/1)
  end

  defp text_like_column?(%{data_type: data_type, udt_name: udt_name}) do
    data_type in ["text", "character varying", "character"] or udt_name == "citext"
  end

  defp count_matches(rule) do
    sql =
      "select count(*) from #{qualified_table(rule)} where #{quoted_identifier(rule.column)} like $1"

    %{rows: [[count]]} = Repo.query!(sql, [match_value(rule)])
    count
  end

  defp delete_matches(rule) do
    sql = "delete from #{qualified_table(rule)} where #{quoted_identifier(rule.column)} like $1"
    %{num_rows: num_rows} = Repo.query!(sql, [match_value(rule)])
    num_rows
  end

  defp match_value(%{match: {:prefix, prefix}}), do: prefix <> "%"

  defp rule_summary(rule, count) do
    %{
      id: rule_key(rule),
      base_rule: rule.id,
      description: rule.description,
      table: "#{rule.schema}.#{rule.table}",
      column: rule.column,
      preview_count: count
    }
  end

  defp skipped_rules(rules) do
    matched_rule_ids = MapSet.new(rules, & &1.id)

    Data.cleanup_rules()
    |> Enum.reject(&MapSet.member?(matched_rule_ids, &1.id))
    |> Enum.map(fn rule ->
      %{
        id: Atom.to_string(rule.id),
        description: rule.description,
        reason: "No matching table columns were found in the connected database."
      }
    end)
  end

  defp warnings([], _preview_counts) do
    ["No supported cleanup targets were found. Nothing will be deleted."]
  end

  defp warnings(rules, preview_counts) do
    zero_match_rules =
      rules
      |> Enum.map(&rule_key/1)
      |> Enum.filter(&(preview_counts[&1] == 0))

    if zero_match_rules == [] do
      []
    else
      ["Some matched cleanup rules currently have zero rows to delete."]
    end
  end

  defp rule_key(rule) do
    "#{rule.id}:#{rule.schema}.#{rule.table}.#{rule.column}"
  end

  defp qualified_table(rule) do
    quoted_identifier(rule.schema) <> "." <> quoted_identifier(rule.table)
  end

  defp quoted_identifier(value) do
    escaped = String.replace(value, "\"", "\"\"")
    ~s("#{escaped}")
  end
end
