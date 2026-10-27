///|
priv struct FakeAgentCli {
  root : String
  executable : String
  record_directory : String
}

///|
priv struct SequenceEvent {
  sequence : Int
} derive(FromJson)

///|
async fn create_fake_agent_cli() -> FakeAgentCli {
  let root = @fs.tmpdir(prefix="agent-cli-sdk-test-")
  let executable = "\{root}/agent"
  let record_directory = "\{root}/records"
  @fs.mkdir(record_directory, recursive=true)
  @fs.write_file(
    executable,
    fake_agent_cli_script(),
    create_mode=CreateOrTruncate,
  )
  @fs.chmod(executable, 0o755)
  { root, executable, record_directory }
}

///|
async fn with_fake_agent_cli(run_test : async (FakeAgentCli) -> Unit) -> Unit {
  let fixture = create_fake_agent_cli()
  run_test(fixture) catch {
    error => {
      @async.protect_from_cancel(async fn() {
        @fs.rmdir(fixture.root, recursive=true)
      })
      raise error
    }
  }
  @fs.rmdir(fixture.root, recursive=true)
}

///|
fn FakeAgentCli::invocation(
  self : FakeAgentCli,
  events : String,
  extra_environment : Map[String, String],
) -> Invocation {
  let environment : Map[String, String] = {
    "PATH": "/usr/bin:/bin",
    "FAKE_AGENT_RECORD_DIR": self.record_directory,
    "FAKE_AGENT_EVENTS": events,
  }
  for key, value in extra_environment {
    environment[key] = value
  }
  Invocation::new(
    command=self.executable,
    arguments=["run", "--format", "json"],
    input="Hello from stdin",
    environment~,
    inherit_environment=false,
  )
}

///|
async fn process_is_running(pid : Int) -> Bool {
  let (code, _, _) = @process.collect_output("kill", ["-0", pid.to_string()])
  code == 0
}

///|
fn fake_agent_cli_script() -> String {
  let script =
    #|#!/bin/sh
    #|set -eu
    #|record_dir="${FAKE_AGENT_RECORD_DIR:?}"
    #|: > "$record_dir/args"
    #|for arg in "$@"; do
    #|  printf '%s\n' "$arg" >> "$record_dir/args"
    #|done
    #|/bin/cat > "$record_dir/input"
    #|/usr/bin/env | /usr/bin/sort > "$record_dir/env"
    #|printf '%s\n' "$$" > "$record_dir/pid"
    #|if [ -n "${FAKE_AGENT_EVENTS-}" ]; then
    #|  printf '%s\n' "$FAKE_AGENT_EVENTS"
    #|fi
    #|if [ -n "${FAKE_AGENT_STDERR-}" ]; then
    #|  printf '%s' "$FAKE_AGENT_STDERR" >&2
    #|fi
    #|if [ "${FAKE_AGENT_PAUSE-}" = "1" ]; then /bin/sleep 30; fi
    #|exit "${FAKE_AGENT_EXIT_CODE-0}"
    #|
  script
}

///|
async test "run decodes ordered JSON events and preserves invocation data" {
  with_fake_agent_cli(async fn(fixture) {
    let events = ["{\"sequence\":1}", "{\"sequence\":2}"].join("\n")
    let received : Array[Int] = []
    let result = run(fixture.invocation(events, { "CUSTOM_ENV": "custom" }), fn(
      event : SequenceEvent,
    ) {
      received.push(event.sequence)
      true
    })
    debug_inspect(result, content="Completed")
    debug_inspect(received, content="[1, 2]")
    let expected_arguments =
      #|run
      #|--format
      #|json
      #|
    inspect(
      @fs.read_file("\{fixture.record_directory}/args").text(),
      content=expected_arguments,
    )
    inspect(
      @fs.read_file("\{fixture.record_directory}/input").text(),
      content="Hello from stdin",
    )
    assert_true(
      @fs.read_file("\{fixture.record_directory}/env")
      .text()
      .contains("CUSTOM_ENV=custom\n"),
    )
  })
}

///|
async test "run returns nonzero exit status and stderr" {
  with_fake_agent_cli(async fn(fixture) {
    let result = run(
      fixture.invocation("", {
        "FAKE_AGENT_STDERR": "agent failed",
        "FAKE_AGENT_EXIT_CODE": "17",
      }),
      fn(_ : Json) { true },
    )
    debug_inspect(result, content="Failed(code=17, stderr=\"agent failed\")")
  })
}

///|
async test "run rejects malformed JSONL and terminates the child" {
  with_fake_agent_cli(async fn(fixture) {
    let invocation = fixture.invocation("{not-json", { "FAKE_AGENT_PAUSE": "1" })
    let message = try {
      run(invocation, fn(_ : Json) { true }) |> ignore
      "no error"
    } catch {
      AgentCliError::InvalidJson(line~, cause~) => "\{line}:\{cause}"
      error => "unexpected: \{error}"
    }
    assert_true(message.has_prefix("{not-json:"))
    let pid = @string.parse_int(
      @fs.read_file("\{fixture.record_directory}/pid").text().trim(),
      base=10,
    )
    assert_false(process_is_running(pid))
  })
}

///|
async test "run rejects JSON events that do not match the requested type" {
  with_fake_agent_cli(async fn(fixture) {
    let invocation = fixture.invocation("{\"unexpected\":true}", {
      "FAKE_AGENT_PAUSE": "1",
    })
    let message = try {
      run(invocation, fn(_ : SequenceEvent) { true }) |> ignore
      "no error"
    } catch {
      AgentCliError::InvalidJson(line~, cause~) => "\{line}:\{cause}"
      error => "unexpected: \{error}"
    }
    assert_true(message.has_prefix("{\"unexpected\":true}:"))
    let pid = @string.parse_int(
      @fs.read_file("\{fixture.record_directory}/pid").text().trim(),
      base=10,
    )
    assert_false(process_is_running(pid))
  })
}

///|
async test "run stops the child when the callback returns false" {
  with_fake_agent_cli(async fn(fixture) {
    let result = run(
      fixture.invocation("{\"sequence\":1}\n{\"sequence\":2}", {
        "FAKE_AGENT_PAUSE": "1",
      }),
      fn(_ : Json) { false },
    )
    debug_inspect(result, content="Stopped")
    let pid = @string.parse_int(
      @fs.read_file("\{fixture.record_directory}/pid").text().trim(),
      base=10,
    )
    assert_false(process_is_running(pid))
  })
}

///|
async test "run cancellation terminates the child" {
  with_fake_agent_cli(async fn(fixture) {
    let started : @aqueue.Queue[Unit] = @aqueue.Queue(kind=@aqueue.Unbounded)
    @async.with_task_group(async fn(group) {
      let task = group.spawn(
        async fn() {
          run(
            fixture.invocation("{\"started\":true}", { "FAKE_AGENT_PAUSE": "1" }),
            async fn(_ : Json) {
              started.put(())
              true
            },
          )
          |> ignore
        },
        allow_failure=true,
      )
      let pid_path = "\{fixture.record_directory}/pid"
      started.get()
      let pid = @string.parse_int(
        @fs.read_file(pid_path).text().trim(),
        base=10,
      )
      assert_true(process_is_running(pid))
      task.cancel()
      let cancelled = try {
        task.wait()
        false
      } catch {
        error => @async.is_cancellation_error(error)
      }
      assert_true(cancelled)
      assert_false(process_is_running(pid))
    })
  })
}
