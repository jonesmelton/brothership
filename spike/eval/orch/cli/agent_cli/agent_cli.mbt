///|
/// A complete invocation of a JSONL-emitting agent CLI.
pub(all) struct Invocation {
  command : String
  arguments : Array[String]
  environment : Map[String, String]
  inherit_environment : Bool
  input : String
}

///|
/// Construct an agent CLI invocation.
pub fn Invocation::new(
  command~ : String,
  arguments~ : Array[String],
  input~ : String,
  environment? : Map[String, String] = Map([]),
  inherit_environment? : Bool = true,
) -> Invocation {
  { command, arguments, environment, inherit_environment, input }
}

///|
/// The process-level outcome of an agent CLI invocation.
pub(all) enum RunResult {
  Completed
  Stopped
  Failed(code~ : Int, stderr~ : String)
} derive(Debug, Eq)

///|
/// Errors raised while reading or decoding the JSONL protocol.
pub(all) suberror AgentCliError {
  InvalidJson(line~ : String, cause~ : String)
} derive(Debug, Eq)

///|
priv enum ChildExit {
  Exited(Int)
  CancelledForStop
}

///|
/// Run an agent CLI, write its stdin, and stream decoded JSONL events in order.
///
/// Returning `false` from `on_event` terminates the child and returns `Stopped`.
/// A nonzero child exit is returned as `Failed`; process and callback errors are
/// raised after all child resources have been cleaned up.
pub async fn[T : @json.FromJson] run(
  invocation : Invocation,
  on_event : async (T) -> Bool,
) -> RunResult {
  let stop_requested = Ref(false)
  @async.with_task_group(async fn(group) {
    let (child_input, input_writer) = @process.write_to_process()
    let (output_reader, child_output) = @process.read_from_process()
    let (error_reader, child_error) = @process.read_from_process()
    group.spawn_bg(async fn() {
      defer input_writer.close()
      input_writer.write(invocation.input)
    })
    let stderr_task = group.spawn(async fn() {
      defer error_reader.close()
      error_reader.read_all().text()
    })
    let child = @process.spawn(
      group,
      invocation.command,
      invocation.arguments,
      extra_env=invocation.environment,
      inherit_env=invocation.inherit_environment,
      stdin=child_input,
      stdout=child_output,
      stderr=child_error,
      cancel_handler=@process.hard_cancel(),
    )
    let stdout_task = group.spawn(async fn() {
      defer output_reader.close()
      while output_reader.read_until("\n") is Some(line) {
        let json = @json.parse(line) catch {
          error => raise AgentCliError::InvalidJson(line~, cause="\{error}")
        }
        let event : T = @json.from_json(json) catch {
          error => raise AgentCliError::InvalidJson(line~, cause="\{error}")
        }
        if !on_event(event) {
          stop_requested.val = true
          child.cancel()
          break
        }
      }
    })
    let child_exit = try {
      let code = child.wait()
      if stop_requested.val {
        CancelledForStop
      } else {
        Exited(code)
      }
    } catch {
      error if stop_requested.val && @async.is_cancellation_error(error) =>
        CancelledForStop
      error => raise error
    }
    let exited_with_failure = match child_exit {
      Exited(code) => code != 0
      CancelledForStop => false
    }
    if exited_with_failure {
      stdout_task.cancel()
      stdout_task.wait() catch {
        error => if !@async.is_cancellation_error(error) { raise error }
      }
    } else {
      stdout_task.wait()
    }
    let stderr = if stop_requested.val {
      stderr_task.cancel()
      try stderr_task.wait() |> ignore catch {
        error => if !@async.is_cancellation_error(error) { raise error }
      }
      ""
    } else {
      stderr_task.wait()
    }
    match child_exit {
      Exited(0) => Completed
      Exited(code) => Failed(code~, stderr~)
      CancelledForStop => Stopped
    }
  })
}
