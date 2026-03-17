defmodule SymphonyElixir.Mcp.TaskTools do
  @moduledoc """
  MCP tool specifications and execution for Symphony task management.

  Provides tools appropriate for the configured tracker kind:
  - `local`: task_show, task_update_state, workpad_show, workpad_update
  - `linear`: linear_graphql
  """

  alias SymphonyElixir.Linear.Client
  alias SymphonyElixir.Tracker.TaskFile

  @task_show "task_show"
  @task_update_state "task_update_state"
  @workpad_show "workpad_show"
  @workpad_update "workpad_update"
  @linear_graphql "linear_graphql"

  @spec tool_specs(String.t() | nil) :: [map()]
  def tool_specs("local") do
    [
      %{
        "name" => @task_show,
        "description" => "Show the active task details (id, identifier, title, state, description, labels).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{},
          "additionalProperties" => false
        }
      },
      %{
        "name" => @task_update_state,
        "description" => "Update the active task state.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["state"],
          "additionalProperties" => false,
          "properties" => %{
            "state" => %{
              "type" => "string",
              "description" => "New state name (e.g. \"In Progress\", \"Agent Review\", \"Done\")."
            }
          }
        }
      },
      %{
        "name" => @workpad_show,
        "description" => "Show the current workpad content for the active task.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{},
          "additionalProperties" => false
        }
      },
      %{
        "name" => @workpad_update,
        "description" => "Replace the workpad content for the active task.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["content"],
          "additionalProperties" => false,
          "properties" => %{
            "content" => %{
              "type" => "string",
              "description" => "Full new workpad content."
            }
          }
        }
      }
    ]
  end

  def tool_specs("linear") do
    [
      %{
        "name" => @linear_graphql,
        "description" => "Execute a raw GraphQL query or mutation against Linear using Symphony's configured auth.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["query"],
          "additionalProperties" => false,
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "GraphQL query or mutation document to execute against Linear."
            },
            "variables" => %{
              "type" => ["object", "null"],
              "description" => "Optional GraphQL variables object.",
              "additionalProperties" => true
            }
          }
        }
      }
    ]
  end

  def tool_specs(_other), do: []

  @spec execute(String.t() | nil, term(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(tool_name, args, opts \\ []) do
    case tool_name do
      @task_show -> execute_task_show(opts)
      @task_update_state -> execute_task_update_state(args, opts)
      @workpad_show -> execute_workpad_show(opts)
      @workpad_update -> execute_workpad_update(args, opts)
      @linear_graphql -> execute_linear_graphql(args, opts)
      other -> {:error, "Unsupported tool: #{inspect(other)}."}
    end
  end

  defp execute_task_show(opts) do
    task_file = resolve_task_file(opts)
    task_reader = Keyword.get(opts, :task_reader, &TaskFile.read/1)

    case task_file do
      nil ->
        {:error, "No task file configured. Set SYMPHONY_TASK_FILE env var."}

      path ->
        case task_reader.(path) do
          {:ok, issue} ->
            {:ok,
             Jason.encode!(
               %{
                 "id" => issue.id,
                 "identifier" => issue.identifier,
                 "title" => issue.title,
                 "state" => issue.state,
                 "description" => issue.description,
                 "labels" => issue.labels
               },
               pretty: true
             )}

          {:error, reason} ->
            {:error, format_file_error(reason)}
        end
    end
  end

  defp execute_task_update_state(args, opts) do
    task_file = resolve_task_file(opts)
    state_updater = Keyword.get(opts, :state_updater, &TaskFile.update_state/2)

    with {:ok, state} <- require_string_arg(args, "state"),
         {:ok, path} <- require_task_file(task_file) do
      case state_updater.(path, state) do
        :ok -> {:ok, "Task state updated to #{inspect(state)}."}
        {:error, reason} -> {:error, format_file_error(reason)}
      end
    end
  end

  defp execute_workpad_show(opts) do
    task_file = resolve_task_file(opts)
    workpad_reader = Keyword.get(opts, :workpad_reader, &TaskFile.read_workpad/1)

    case task_file do
      nil ->
        {:error, "No task file configured. Set SYMPHONY_TASK_FILE env var."}

      path ->
        case workpad_reader.(path) do
          {:ok, nil} -> {:ok, ""}
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, format_file_error(reason)}
        end
    end
  end

  defp execute_workpad_update(args, opts) do
    task_file = resolve_task_file(opts)
    workpad_updater = Keyword.get(opts, :workpad_updater, &TaskFile.update_workpad/2)

    with {:ok, content} <- require_string_arg(args, "content"),
         {:ok, path} <- require_task_file(task_file) do
      case workpad_updater.(path, content) do
        :ok -> {:ok, "Workpad updated."}
        {:error, reason} -> {:error, format_file_error(reason)}
      end
    end
  end

  defp execute_linear_graphql(args, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_args(args),
         {:ok, response} <- linear_client.(query, variables, []) do
      text = encode_response(response)

      case graphql_has_errors?(response) do
        true -> {:error, text}
        false -> {:ok, text}
      end
    else
      {:error, :missing_query} ->
        {:error, "`linear_graphql` requires a non-empty `query` string."}

      {:error, :invalid_arguments} ->
        {:error, "`linear_graphql` expects an object with `query` and optional `variables`."}

      {:error, :invalid_variables} ->
        {:error, "`linear_graphql.variables` must be a JSON object when provided."}

      {:error, :missing_linear_api_token} ->
        {:error, "Symphony is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."}

      {:error, {:linear_api_status, status}} ->
        {:error, "Linear GraphQL request failed with HTTP #{status}."}

      {:error, {:linear_api_request, reason}} ->
        {:error, "Linear GraphQL request failed before receiving a response: #{inspect(reason)}."}

      {:error, reason} ->
        {:error, "Linear GraphQL tool execution failed: #{inspect(reason)}."}
    end
  end

  defp resolve_task_file(opts) do
    case Keyword.get(opts, :task_file) do
      path when is_binary(path) and path != "" ->
        path

      _ ->
        case Application.get_env(:symphony_elixir, :local_tracker_task_file) do
          path when is_binary(path) and path != "" -> path
          _ -> System.get_env("SYMPHONY_TASK_FILE")
        end
    end
  end

  defp require_task_file(nil),
    do: {:error, "No task file configured. Set SYMPHONY_TASK_FILE env var."}

  defp require_task_file(path), do: {:ok, path}

  defp require_string_arg(args, key) when is_map(args) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error, "Missing required argument: #{inspect(key)}."}
    end
  end

  defp normalize_linear_args(args) when is_map(args) do
    with {:ok, trimmed} <- extract_query(args) do
      normalize_variables(trimmed, args)
    end
  end

  defp normalize_linear_args(args) when is_binary(args) do
    trimmed = String.trim(args)
    if trimmed == "", do: {:error, :missing_query}, else: {:ok, trimmed, %{}}
  end

  defp normalize_linear_args(_args), do: {:error, :invalid_arguments}

  defp extract_query(args) do
    case Map.get(args, "query") || Map.get(args, :query) do
      query when is_binary(query) and query != "" ->
        trimmed = String.trim(query)
        if trimmed == "", do: {:error, :missing_query}, else: {:ok, trimmed}

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(trimmed, args) do
    case Map.get(args, "variables") || Map.get(args, :variables) || %{} do
      vars when is_map(vars) -> {:ok, trimmed, vars}
      _ -> {:error, :invalid_variables}
    end
  end

  defp graphql_has_errors?(%{"errors" => errors}) when is_list(errors) and errors != [], do: true
  defp graphql_has_errors?(%{errors: errors}) when is_list(errors) and errors != [], do: true
  defp graphql_has_errors?(_response), do: false

  defp encode_response(response) when is_map(response) or is_list(response) do
    Jason.encode!(response, pretty: true)
  end

  defp encode_response(response), do: inspect(response)

  defp format_file_error({:task_file_read_error, path, reason}) do
    "Failed to read task file #{inspect(path)}: #{inspect(reason)}."
  end

  defp format_file_error({:task_file_parse_error, path, reason}) do
    "Failed to parse task file #{inspect(path)}: #{inspect(reason)}."
  end

  defp format_file_error(reason) do
    "Task file operation failed: #{inspect(reason)}."
  end
end
