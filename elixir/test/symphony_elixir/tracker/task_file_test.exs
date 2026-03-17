defmodule SymphonyElixir.Tracker.TaskFileTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.Tracker.TaskFile

  setup do
    dir = Path.join(System.tmp_dir!(), "task_file_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "task.json")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, path: path}
  end

  defp write_raw_json(path, content), do: File.write!(path, content)

  defp sample_issue do
    %Issue{
      id: "task-uuid-1",
      identifier: "SYM-3",
      title: "Expose Symphony task tooling",
      state: "In Progress",
      description: "Some description",
      labels: ["mcp", "claude"]
    }
  end

  test "write then read round-trips all Issue fields", %{path: path} do
    issue = sample_issue()
    assert :ok = TaskFile.write(path, issue)

    assert {:ok, read_back} = TaskFile.read(path)
    assert read_back.id == issue.id
    assert read_back.identifier == issue.identifier
    assert read_back.title == issue.title
    assert read_back.state == issue.state
    assert read_back.description == issue.description
    assert read_back.labels == issue.labels
  end

  test "write then read with nil description and empty labels", %{path: path} do
    issue = %Issue{
      id: "id-1",
      identifier: "X-1",
      title: "T",
      state: "Todo",
      description: nil,
      labels: []
    }

    assert :ok = TaskFile.write(path, issue)
    assert {:ok, read_back} = TaskFile.read(path)
    assert read_back.description == nil
    assert read_back.labels == []
  end

  test "read returns error when file does not exist", %{path: path} do
    assert {:error, {:task_file_read_error, ^path, :enoent}} = TaskFile.read(path)
  end

  test "read returns parse error when file is not valid JSON", %{path: path} do
    write_raw_json(path, "not json")
    assert {:error, {:task_file_parse_error, ^path, _}} = TaskFile.read(path)
  end

  test "read returns parse error when JSON is not a map", %{path: path} do
    write_raw_json(path, "[1, 2, 3]")
    assert {:error, {:task_file_parse_error, ^path, :not_a_map}} = TaskFile.read(path)
  end

  test "read_workpad returns nil when no workpad field is set", %{path: path} do
    issue = sample_issue()
    TaskFile.write(path, issue)
    assert {:ok, nil} = TaskFile.read_workpad(path)
  end

  test "read_workpad returns the workpad after update_workpad", %{path: path} do
    issue = sample_issue()
    TaskFile.write(path, issue)
    content = "## Codex Workpad\n\nSome notes"
    assert :ok = TaskFile.update_workpad(path, content)
    assert {:ok, ^content} = TaskFile.read_workpad(path)
  end

  test "update_workpad preserves other fields", %{path: path} do
    issue = sample_issue()
    TaskFile.write(path, issue)
    assert :ok = TaskFile.update_workpad(path, "workpad content")
    assert {:ok, read_back} = TaskFile.read(path)
    assert read_back.state == issue.state
    assert read_back.title == issue.title
  end

  test "update_state changes the state and preserves other fields", %{path: path} do
    issue = sample_issue()
    TaskFile.write(path, issue)
    assert :ok = TaskFile.update_state(path, "Agent Review")
    assert {:ok, read_back} = TaskFile.read(path)
    assert read_back.state == "Agent Review"
    assert read_back.title == issue.title
    assert read_back.identifier == issue.identifier
  end

  test "read_workpad returns error when file does not exist", %{path: path} do
    assert {:error, {:task_file_read_error, ^path, :enoent}} = TaskFile.read_workpad(path)
  end

  test "read_workpad returns parse error for invalid JSON", %{path: path} do
    write_raw_json(path, "bad")
    assert {:error, {:task_file_parse_error, ^path, _}} = TaskFile.read_workpad(path)
  end

  test "read_workpad returns parse error when JSON is not a map", %{path: path} do
    write_raw_json(path, "42")
    assert {:error, {:task_file_parse_error, ^path, :not_a_map}} = TaskFile.read_workpad(path)
  end

  test "update_state returns error when file does not exist", %{path: path} do
    assert {:error, {:task_file_read_error, ^path, :enoent}} =
             TaskFile.update_state(path, "Done")
  end

  test "update_state returns parse error for invalid JSON", %{path: path} do
    write_raw_json(path, "bad")
    assert {:error, {:task_file_parse_error, ^path, _}} = TaskFile.update_state(path, "Done")
  end

  test "update_state returns parse error when JSON is not a map", %{path: path} do
    write_raw_json(path, "null")

    assert {:error, {:task_file_parse_error, ^path, :not_a_map}} =
             TaskFile.update_state(path, "Done")
  end

  test "update_workpad returns error when file does not exist", %{path: path} do
    assert {:error, {:task_file_read_error, ^path, :enoent}} =
             TaskFile.update_workpad(path, "content")
  end

  test "update_workpad returns parse error for invalid JSON", %{path: path} do
    write_raw_json(path, "bad")

    assert {:error, {:task_file_parse_error, ^path, _}} =
             TaskFile.update_workpad(path, "content")
  end

  test "update_workpad returns parse error when JSON is not a map", %{path: path} do
    write_raw_json(path, "true")

    assert {:error, {:task_file_parse_error, ^path, :not_a_map}} =
             TaskFile.update_workpad(path, "content")
  end
end
