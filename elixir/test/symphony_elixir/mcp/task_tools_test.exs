defmodule SymphonyElixir.Mcp.TaskToolsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.Mcp.TaskTools
  alias SymphonyElixir.Tracker.TaskFile

  setup do
    dir = Path.join(System.tmp_dir!(), "task_tools_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "task.json")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, path: path}
  end

  defp sample_issue do
    %Issue{
      id: "uuid-1",
      identifier: "SYM-3",
      title: "Expose Symphony task tooling",
      state: "In Progress",
      description: "MCP tools for Claude",
      labels: ["mcp", "claude"]
    }
  end

  defp write_task(path) do
    TaskFile.write(path, sample_issue())
    path
  end

  # --- tool_specs ---

  test "tool_specs for local returns four tools with correct names" do
    specs = TaskTools.tool_specs("local")
    names = Enum.map(specs, & &1["name"])
    assert "task_show" in names
    assert "task_update_state" in names
    assert "workpad_show" in names
    assert "workpad_update" in names
    assert length(specs) == 4
  end

  test "tool_specs for linear returns linear_graphql only" do
    specs = TaskTools.tool_specs("linear")
    assert [%{"name" => "linear_graphql"}] = specs
  end

  test "tool_specs for unknown tracker returns empty list" do
    assert [] = TaskTools.tool_specs("other")
    assert [] = TaskTools.tool_specs(nil)
  end

  # --- task_show ---

  test "task_show returns task details as JSON", %{path: path} do
    write_task(path)
    issue = sample_issue()

    assert {:ok, json} = TaskTools.execute("task_show", %{}, task_file: path)
    decoded = Jason.decode!(json)
    assert decoded["identifier"] == issue.identifier
    assert decoded["title"] == issue.title
    assert decoded["state"] == issue.state
    assert decoded["labels"] == issue.labels
  end

  test "task_show returns error when no task file configured" do
    assert {:error, message} = TaskTools.execute("task_show", %{}, task_file: nil)
    assert message =~ "SYMPHONY_TASK_FILE"
  end

  test "task_show returns error when task file does not exist", %{path: path} do
    assert {:error, message} = TaskTools.execute("task_show", %{}, task_file: path)
    assert message =~ "task file"
  end

  test "task_show uses injectable task_reader", %{path: path} do
    fake_reader = fn _p ->
      {:ok, %Issue{id: "x", identifier: "X-1", title: "T", state: "Todo", labels: []}}
    end

    assert {:ok, json} =
             TaskTools.execute("task_show", %{}, task_file: path, task_reader: fake_reader)

    decoded = Jason.decode!(json)
    assert decoded["identifier"] == "X-1"
  end

  test "task_show handles reader error via injectable reader", %{path: path} do
    fake_reader = fn p -> {:error, {:task_file_read_error, p, :enoent}} end

    assert {:error, message} =
             TaskTools.execute("task_show", %{}, task_file: path, task_reader: fake_reader)

    assert message =~ "task file"
  end

  # --- task_update_state ---

  test "task_update_state updates state and returns confirmation", %{path: path} do
    write_task(path)

    assert {:ok, message} =
             TaskTools.execute("task_update_state", %{"state" => "Agent Review"}, task_file: path)

    assert message =~ "Agent Review"

    assert {:ok, [%{state: "Agent Review"}]} =
             {:ok, path}
             |> then(fn {:ok, p} -> TaskFile.read(p) end)
             |> then(fn {:ok, issue} -> {:ok, [issue]} end)
  end

  test "task_update_state uses injectable state_updater" do
    parent = self()

    updater = fn path, state ->
      send(parent, {:update_called, path, state})
      :ok
    end

    assert {:ok, _} =
             TaskTools.execute("task_update_state", %{"state" => "Done"},
               task_file: "/tmp/some.json",
               state_updater: updater
             )

    assert_received {:update_called, "/tmp/some.json", "Done"}
  end

  test "task_update_state returns error when state argument is missing" do
    assert {:error, message} =
             TaskTools.execute("task_update_state", %{}, task_file: "/tmp/x.json")

    assert message =~ "state"
  end

  test "task_update_state returns error when state argument is blank" do
    assert {:error, message} =
             TaskTools.execute("task_update_state", %{"state" => ""}, task_file: "/tmp/x.json")

    assert message =~ "state"
  end

  test "task_update_state returns error when no task file" do
    assert {:error, message} =
             TaskTools.execute("task_update_state", %{"state" => "Done"}, task_file: nil)

    assert message =~ "SYMPHONY_TASK_FILE"
  end

  test "task_update_state returns error when state_updater fails" do
    updater = fn path, _state ->
      {:error, {:task_file_read_error, path, :enoent}}
    end

    assert {:error, message} =
             TaskTools.execute("task_update_state", %{"state" => "Done"},
               task_file: "/tmp/x.json",
               state_updater: updater
             )

    assert message =~ "task file"
  end

  # --- workpad_show ---

  test "workpad_show returns empty string when workpad is nil", %{path: path} do
    write_task(path)
    assert {:ok, ""} = TaskTools.execute("workpad_show", %{}, task_file: path)
  end

  test "workpad_show returns workpad content when set", %{path: path} do
    write_task(path)
    TaskFile.update_workpad(path, "## Codex Workpad\nstuff")
    assert {:ok, "## Codex Workpad\nstuff"} = TaskTools.execute("workpad_show", %{}, task_file: path)
  end

  test "workpad_show returns error when no task file" do
    assert {:error, message} = TaskTools.execute("workpad_show", %{}, task_file: nil)
    assert message =~ "SYMPHONY_TASK_FILE"
  end

  test "workpad_show uses injectable workpad_reader" do
    reader = fn _path -> {:ok, "injected workpad"} end

    assert {:ok, "injected workpad"} =
             TaskTools.execute("workpad_show", %{},
               task_file: "/tmp/x.json",
               workpad_reader: reader
             )
  end

  test "workpad_show returns error on reader failure" do
    reader = fn path -> {:error, {:task_file_read_error, path, :enoent}} end

    assert {:error, message} =
             TaskTools.execute("workpad_show", %{},
               task_file: "/tmp/x.json",
               workpad_reader: reader
             )

    assert message =~ "task file"
  end

  # --- workpad_update ---

  test "workpad_update replaces workpad content", %{path: path} do
    write_task(path)

    assert {:ok, "Workpad updated."} =
             TaskTools.execute("workpad_update", %{"content" => "new workpad"}, task_file: path)

    assert {:ok, "new workpad"} = TaskFile.read_workpad(path)
  end

  test "workpad_update uses injectable workpad_updater" do
    parent = self()

    updater = fn path, content ->
      send(parent, {:update_called, path, content})
      :ok
    end

    assert {:ok, _} =
             TaskTools.execute("workpad_update", %{"content" => "data"},
               task_file: "/tmp/x.json",
               workpad_updater: updater
             )

    assert_received {:update_called, "/tmp/x.json", "data"}
  end

  test "workpad_update returns error when content argument is missing" do
    assert {:error, message} =
             TaskTools.execute("workpad_update", %{}, task_file: "/tmp/x.json")

    assert message =~ "content"
  end

  test "workpad_update returns error when content argument is blank" do
    assert {:error, message} =
             TaskTools.execute("workpad_update", %{"content" => ""}, task_file: "/tmp/x.json")

    assert message =~ "content"
  end

  test "workpad_update returns error when no task file" do
    assert {:error, message} =
             TaskTools.execute("workpad_update", %{"content" => "x"}, task_file: nil)

    assert message =~ "SYMPHONY_TASK_FILE"
  end

  test "workpad_update returns error when workpad_updater fails" do
    updater = fn path, _content ->
      {:error, {:task_file_read_error, path, :enoent}}
    end

    assert {:error, message} =
             TaskTools.execute("workpad_update", %{"content" => "x"},
               task_file: "/tmp/x.json",
               workpad_updater: updater
             )

    assert message =~ "task file"
  end

  # --- linear_graphql ---

  test "linear_graphql executes query and returns successful result" do
    parent = self()

    client = fn query, variables, opts ->
      send(parent, {:called, query, variables, opts})
      {:ok, %{"data" => %{"viewer" => %{"id" => "u1"}}}}
    end

    assert {:ok, json} =
             TaskTools.execute(
               "linear_graphql",
               %{"query" => "query Viewer { viewer { id } }"},
               linear_client: client
             )

    assert_received {:called, "query Viewer { viewer { id } }", %{}, []}
    decoded = Jason.decode!(json)
    assert decoded["data"]["viewer"]["id"] == "u1"
  end

  test "linear_graphql returns error for GraphQL error responses" do
    client = fn _query, _vars, _opts ->
      {:ok, %{"errors" => [%{"message" => "boom"}]}}
    end

    assert {:error, json} =
             TaskTools.execute(
               "linear_graphql",
               %{"query" => "query { bad }"},
               linear_client: client
             )

    decoded = Jason.decode!(json)
    assert [%{"message" => "boom"}] = decoded["errors"]
  end

  test "linear_graphql returns error for missing query" do
    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{}, linear_client: fn _, _, _ -> flunk("should not call client") end)

    assert message =~ "query"
  end

  test "linear_graphql returns error for blank query" do
    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "  "}, linear_client: fn _, _, _ -> flunk("should not call client") end)

    assert message =~ "query"
  end

  test "linear_graphql returns error for invalid arguments" do
    assert {:error, message} =
             TaskTools.execute("linear_graphql", [:bad], linear_client: fn _, _, _ -> flunk("should not call client") end)

    assert message =~ "object"
  end

  test "linear_graphql returns error for invalid variables" do
    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "q", "variables" => [1, 2]}, linear_client: fn _, _, _ -> flunk("should not call client") end)

    assert message =~ "variables"
  end

  test "linear_graphql passes variables to client" do
    parent = self()

    client = fn query, variables, _opts ->
      send(parent, {:called, query, variables})
      {:ok, %{}}
    end

    TaskTools.execute(
      "linear_graphql",
      %{"query" => "q", "variables" => %{"id" => "abc"}},
      linear_client: client
    )

    assert_received {:called, "q", %{"id" => "abc"}}
  end

  test "linear_graphql handles missing auth token error" do
    client = fn _q, _v, _o -> {:error, :missing_linear_api_token} end

    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    assert message =~ "Linear auth"
  end

  test "linear_graphql handles HTTP status errors" do
    client = fn _q, _v, _o -> {:error, {:linear_api_status, 503}} end

    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    assert message =~ "503"
  end

  test "linear_graphql handles request errors" do
    client = fn _q, _v, _o -> {:error, {:linear_api_request, :timeout}} end

    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    assert message =~ "timeout"
  end

  test "linear_graphql handles unexpected client errors" do
    client = fn _q, _v, _o -> {:error, :unexpected} end

    assert {:error, message} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    assert message =~ "unexpected"
  end

  test "linear_graphql accepts raw query string" do
    client = fn query, _vars, _opts -> {:ok, %{"query" => query}} end

    assert {:ok, _} =
             TaskTools.execute(
               "linear_graphql",
               "query Viewer { viewer { id } }",
               linear_client: client
             )
  end

  test "linear_graphql encodes non-map responses with inspect" do
    client = fn _q, _v, _o -> {:ok, :atom_response} end

    assert {:ok, text} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    assert text == ":atom_response"
  end

  # --- resolve_task_file via app env ---

  test "task_show resolves task_file from app env when no :task_file opt", %{path: path} do
    write_task(path)
    Application.put_env(:symphony_elixir, :local_tracker_task_file, path)
    on_exit(fn -> Application.delete_env(:symphony_elixir, :local_tracker_task_file) end)

    assert {:ok, json} = TaskTools.execute("task_show", %{})
    decoded = Jason.decode!(json)
    assert decoded["identifier"] == "SYM-3"
  end

  # --- graphql atom-key errors ---

  test "linear_graphql handles atom-keyed error responses" do
    client = fn _q, _v, _o -> {:ok, %{errors: [%{message: "atom boom"}]}} end

    assert {:error, json} =
             TaskTools.execute("linear_graphql", %{"query" => "q"}, linear_client: client)

    # The json is the encoded response; the error branch was taken
    assert is_binary(json)
  end

  # --- parse error format_file_error path ---

  test "task_show formats parse errors correctly" do
    reader = fn p -> {:error, {:task_file_parse_error, p, :invalid_json}} end

    assert {:error, message} =
             TaskTools.execute("task_show", %{},
               task_file: "/tmp/x.json",
               task_reader: reader
             )

    assert message =~ "parse"
  end

  # --- catch-all format_file_error path ---

  test "task_show formats unexpected errors correctly" do
    reader = fn _p -> {:error, :some_unknown_error} end

    assert {:error, message} =
             TaskTools.execute("task_show", %{},
               task_file: "/tmp/x.json",
               task_reader: reader
             )

    assert message =~ "Task file operation failed"
  end

  # --- unsupported tool ---

  test "unsupported tool name returns error" do
    assert {:error, message} = TaskTools.execute("not_a_real_tool", %{})
    assert message =~ "not_a_real_tool"
  end

  test "nil tool name returns error" do
    assert {:error, message} = TaskTools.execute(nil, %{})
    assert message =~ "Unsupported"
  end
end
