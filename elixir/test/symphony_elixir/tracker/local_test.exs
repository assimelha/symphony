defmodule SymphonyElixir.Tracker.LocalTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.Tracker.Local
  alias SymphonyElixir.Tracker.TaskFile

  setup do
    dir = Path.join(System.tmp_dir!(), "local_tracker_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "task.json")
    Application.put_env(:symphony_elixir, :local_tracker_task_file, path)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :local_tracker_task_file)
      File.rm_rf!(dir)
    end)

    {:ok, path: path}
  end

  defp write_task(path, overrides \\ []) do
    issue = %Issue{
      id: Keyword.get(overrides, :id, "task-1"),
      identifier: Keyword.get(overrides, :identifier, "SYM-1"),
      title: Keyword.get(overrides, :title, "Test task"),
      state: Keyword.get(overrides, :state, "In Progress"),
      description: Keyword.get(overrides, :description, "desc"),
      labels: Keyword.get(overrides, :labels, ["mcp"])
    }

    TaskFile.write(path, issue)
    issue
  end

  test "fetch_candidate_issues returns empty list when no task file configured" do
    Application.delete_env(:symphony_elixir, :local_tracker_task_file)
    assert {:ok, []} = Local.fetch_candidate_issues()
  end

  test "fetch_candidate_issues returns empty list when task file does not exist", %{path: path} do
    refute File.exists?(path)
    assert {:ok, []} = Local.fetch_candidate_issues()
  end

  test "fetch_candidate_issues returns the issue from the task file", %{path: path} do
    issue = write_task(path)
    assert {:ok, [%Issue{identifier: "SYM-1"}]} = Local.fetch_candidate_issues()
    assert {:ok, [fetched]} = Local.fetch_candidate_issues()
    assert fetched.id == issue.id
    assert fetched.state == issue.state
  end

  test "fetch_issues_by_states returns matching issues", %{path: path} do
    write_task(path, state: "In Progress")

    assert {:ok, [%Issue{}]} = Local.fetch_issues_by_states(["In Progress"])
    assert {:ok, [%Issue{}]} = Local.fetch_issues_by_states(["in progress"])
    assert {:ok, []} = Local.fetch_issues_by_states(["Done"])
    assert {:ok, []} = Local.fetch_issues_by_states([])
  end

  test "fetch_issues_by_states normalizes state case", %{path: path} do
    write_task(path, state: "Agent Review")
    assert {:ok, [_]} = Local.fetch_issues_by_states(["AGENT REVIEW"])
    assert {:ok, [_]} = Local.fetch_issues_by_states(["agent review"])
    assert {:ok, [_]} = Local.fetch_issues_by_states(["Agent Review"])
  end

  test "fetch_issues_by_states returns empty when no file exists" do
    Application.delete_env(:symphony_elixir, :local_tracker_task_file)
    assert {:ok, []} = Local.fetch_issues_by_states(["In Progress"])
  end

  test "fetch_issue_states_by_ids returns matching issues", %{path: path} do
    issue = write_task(path, id: "task-abc")
    assert {:ok, [%Issue{id: "task-abc"}]} = Local.fetch_issue_states_by_ids(["task-abc"])
    assert {:ok, []} = Local.fetch_issue_states_by_ids(["other-id"])
    assert {:ok, []} = Local.fetch_issue_states_by_ids([])
    assert {:ok, [found]} = Local.fetch_issue_states_by_ids(["task-abc"])
    assert found.state == issue.state
  end

  test "fetch_issue_states_by_ids returns empty when no file exists" do
    Application.delete_env(:symphony_elixir, :local_tracker_task_file)
    assert {:ok, []} = Local.fetch_issue_states_by_ids(["task-1"])
  end

  test "create_comment updates the workpad in the task file", %{path: path} do
    write_task(path)
    assert :ok = Local.create_comment("task-1", "## Codex Workpad\n\nstuff")
    assert {:ok, "## Codex Workpad\n\nstuff"} = TaskFile.read_workpad(path)
  end

  test "create_comment returns error when no task file configured" do
    Application.delete_env(:symphony_elixir, :local_tracker_task_file)
    assert {:error, :no_task_file} = Local.create_comment("task-1", "content")
  end

  test "update_issue_state changes state in the task file", %{path: path} do
    write_task(path, state: "In Progress")
    assert :ok = Local.update_issue_state("task-1", "Agent Review")
    assert {:ok, [%Issue{state: "Agent Review"}]} = Local.fetch_candidate_issues()
  end

  test "update_issue_state returns error when no task file configured" do
    Application.delete_env(:symphony_elixir, :local_tracker_task_file)
    assert {:error, :no_task_file} = Local.update_issue_state("task-1", "Done")
  end

  test "fetch_issues_by_states handles nil issue state gracefully", %{path: path} do
    # Write a task that will be decoded with a nil state
    File.write!(path, Jason.encode!(%{"id" => "t1", "identifier" => "X-1", "title" => "T", "state" => nil, "labels" => []}))
    # nil state normalizes to "" which doesn't match non-empty state filters
    assert {:ok, []} = Local.fetch_issues_by_states(["In Progress"])
  end
end
