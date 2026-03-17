defmodule SymphonyElixir.Mcp.Server do
  @moduledoc """
  MCP stdio server exposing Symphony task tooling to Claude.

  Started via `symphony mcp-server [--tracker-kind <kind>] [--task-file <path>]`.

  Speaks the Model Context Protocol (JSON-RPC 2.0) over stdio and exposes
  task management tools scoped to the active task. Tool availability depends
  on the configured tracker kind:
  - `local`:  task_show, task_update_state, workpad_show, workpad_update
  - `linear`: linear_graphql
  """

  alias SymphonyElixir.Mcp.TaskTools

  @protocol_version "2024-11-05"
  @server_name "symphony"
  @server_version "0.1.0"

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          tracker_kind: :string,
          task_file: :string,
          task_id: :string
        ]
      )

    tracker_kind =
      Keyword.get(opts, :tracker_kind) ||
        System.get_env("SYMPHONY_TRACKER_KIND") ||
        "local"

    task_file =
      Keyword.get(opts, :task_file) ||
        Application.get_env(:symphony_elixir, :local_tracker_task_file) ||
        System.get_env("SYMPHONY_TASK_FILE")

    serve(tracker_kind, task_file)
  end

  defp serve(tracker_kind, task_file) do
    tool_specs = TaskTools.tool_specs(tracker_kind)
    loop(tracker_kind, task_file, tool_specs)
  end

  defp loop(tracker_kind, task_file, tool_specs) do
    case read_line() do
      :eof ->
        :ok

      {:ok, line} ->
        case Jason.decode(line) do
          {:ok, message} ->
            handle(message, tracker_kind, task_file, tool_specs)

          {:error, _reason} ->
            :ok
        end

        loop(tracker_kind, task_file, tool_specs)
    end
  end

  defp read_line do
    case IO.read(:stdio, :line) do
      :eof -> :eof
      {:error, _reason} -> :eof
      line when is_binary(line) -> {:ok, String.trim(line)}
    end
  end

  defp handle(%{"method" => "initialize", "id" => id}, _tracker_kind, _task_file, _tool_specs) do
    respond(id, %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{
        "tools" => %{}
      },
      "serverInfo" => %{
        "name" => @server_name,
        "version" => @server_version
      }
    })
  end

  defp handle(%{"method" => "initialized"}, _tracker_kind, _task_file, _tool_specs) do
    :ok
  end

  defp handle(%{"method" => "tools/list", "id" => id}, _tracker_kind, _task_file, tool_specs) do
    respond(id, %{"tools" => tool_specs})
  end

  defp handle(
         %{"method" => "tools/call", "id" => id, "params" => params},
         tracker_kind,
         task_file,
         _tool_specs
       ) do
    tool_name = Map.get(params, "name")
    args = Map.get(params, "arguments") || %{}

    result =
      TaskTools.execute(tool_name, args,
        task_file: task_file,
        tracker_kind: tracker_kind
      )

    respond(id, format_tool_result(result))
  end

  defp handle(%{"method" => "ping", "id" => id}, _tracker_kind, _task_file, _tool_specs) do
    respond(id, %{})
  end

  defp handle(_message, _tracker_kind, _task_file, _tool_specs) do
    :ok
  end

  defp respond(id, result) do
    message = Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
    IO.puts(message)
  end

  defp format_tool_result({:ok, text}) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "isError" => false
    }
  end

  defp format_tool_result({:error, text}) do
    %{
      "content" => [%{"type" => "text", "text" => text}],
      "isError" => true
    }
  end
end
