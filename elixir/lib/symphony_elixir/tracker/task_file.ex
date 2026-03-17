defmodule SymphonyElixir.Tracker.TaskFile do
  @moduledoc """
  Reads and writes local task state from/to a JSON file.

  The task file is a JSON document that stores all local task metadata
  including state and workpad content.
  """

  alias SymphonyElixir.Linear.Issue

  @spec read(Path.t()) :: {:ok, Issue.t()} | {:error, term()}
  def read(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} when is_map(data) <- Jason.decode(contents) do
      {:ok, decode_issue(data)}
    else
      {:ok, _} -> {:error, {:task_file_parse_error, path, :not_a_map}}
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:task_file_parse_error, path, reason}}
      {:error, posix} when is_atom(posix) -> {:error, {:task_file_read_error, path, posix}}
    end
  end

  @spec read_workpad(Path.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def read_workpad(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} when is_map(data) <- Jason.decode(contents) do
      {:ok, Map.get(data, "workpad")}
    else
      {:ok, _} -> {:error, {:task_file_parse_error, path, :not_a_map}}
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:task_file_parse_error, path, reason}}
      {:error, posix} when is_atom(posix) -> {:error, {:task_file_read_error, path, posix}}
    end
  end

  @spec update_state(Path.t(), String.t()) :: :ok | {:error, term()}
  def update_state(path, state_name) when is_binary(path) and is_binary(state_name) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} when is_map(data) <- Jason.decode(contents) do
      write_json(path, Map.put(data, "state", state_name))
    else
      {:ok, _} -> {:error, {:task_file_parse_error, path, :not_a_map}}
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:task_file_parse_error, path, reason}}
      {:error, posix} when is_atom(posix) -> {:error, {:task_file_read_error, path, posix}}
    end
  end

  @spec update_workpad(Path.t(), String.t()) :: :ok | {:error, term()}
  def update_workpad(path, workpad) when is_binary(path) and is_binary(workpad) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} when is_map(data) <- Jason.decode(contents) do
      write_json(path, Map.put(data, "workpad", workpad))
    else
      {:ok, _} -> {:error, {:task_file_parse_error, path, :not_a_map}}
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:task_file_parse_error, path, reason}}
      {:error, posix} when is_atom(posix) -> {:error, {:task_file_read_error, path, posix}}
    end
  end

  @spec write(Path.t(), Issue.t()) :: :ok | {:error, term()}
  def write(path, %Issue{} = issue) when is_binary(path) do
    write_json(path, encode_issue(issue))
  end

  defp write_json(path, data) do
    File.write(path, Jason.encode!(data, pretty: true))
  end

  defp decode_issue(data) when is_map(data) do
    %Issue{
      id: Map.get(data, "id"),
      identifier: Map.get(data, "identifier"),
      title: Map.get(data, "title"),
      state: Map.get(data, "state"),
      description: Map.get(data, "description"),
      labels: Map.get(data, "labels") || []
    }
  end

  defp encode_issue(%Issue{} = issue) do
    %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "title" => issue.title,
      "state" => issue.state,
      "description" => issue.description,
      "labels" => issue.labels || []
    }
  end
end
