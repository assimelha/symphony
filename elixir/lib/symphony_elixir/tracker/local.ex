defmodule SymphonyElixir.Tracker.Local do
  @moduledoc """
  File-backed local tracker adapter.

  Reads and writes task state from a JSON file. The task file path is resolved
  from the `local_tracker_task_file` application env key or the
  `SYMPHONY_TASK_FILE` environment variable.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Tracker.TaskFile

  @impl true
  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    case task_file_path() do
      nil ->
        {:ok, []}

      path ->
        case TaskFile.read(path) do
          {:ok, issue} -> {:ok, [issue]}
          {:error, _reason} -> {:ok, []}
        end
    end
  end

  @impl true
  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(state_names) do
    normalized = MapSet.new(state_names, &normalize_state/1)

    with {:ok, issues} <- fetch_candidate_issues() do
      {:ok,
       Enum.filter(issues, fn %{state: state} ->
         MapSet.member?(normalized, normalize_state(state))
       end)}
    end
  end

  @impl true
  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    wanted = MapSet.new(issue_ids)

    with {:ok, issues} <- fetch_candidate_issues() do
      {:ok,
       Enum.filter(issues, fn %{id: id} ->
         MapSet.member?(wanted, id)
       end)}
    end
  end

  @impl true
  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(_issue_id, body) do
    case task_file_path() do
      nil -> {:error, :no_task_file}
      path -> TaskFile.update_workpad(path, body)
    end
  end

  @impl true
  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(_issue_id, state_name) do
    case task_file_path() do
      nil -> {:error, :no_task_file}
      path -> TaskFile.update_state(path, state_name)
    end
  end

  defp task_file_path do
    case Application.get_env(:symphony_elixir, :local_tracker_task_file) do
      path when is_binary(path) and path != "" -> path
      _ -> System.get_env("SYMPHONY_TASK_FILE")
    end
  end

  defp normalize_state(state) when is_binary(state) do
    state |> String.trim() |> String.downcase()
  end

  defp normalize_state(_state), do: ""
end
