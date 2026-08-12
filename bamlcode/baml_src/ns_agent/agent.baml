// bamlcode — a tiny Claude Code, written entirely in BAML.
//
// An agentic coding CLI built on BAML's ai.Agent runner.
//
//   Interactive REPL:   baml run agent.main
//   One-shot:           baml run agent.ask --json-args '{"task": "summarize this repo"}'

class AgentAnswer {
    message: string,
}

class Turn {
    answer: string,
    transcript: string,
    steps: int,
    // Set when the user cancelled mid-turn with esc + enter. `queued` holds
    // any lines they typed while the turn ran, to run after it.
    interrupted: bool,
    queued: string[],
}

// The result of peeking at stdin during a turn: esc + enter requests a
// cancel; any other typed line is staged in `queued` to run afterwards.
class Interrupt {
    cancel: bool,
    queued: string,
}

function code(history: string, task: string) -> AgentAnswer {
    client: Brain
    tools: [read_file, write_file, edit_file, list_dir, run_bash]
    prompt: `
        You are bamlcode, a CLI coding agent operating inside the user's current
        working directory. Complete the user's task with the available tools.

        Operating rules:
          - Inspect relevant files before changing them.
          - edit_file replaces the FIRST exact occurrence of old_str, so make old_str unique
            and copy it byte-for-byte from the file (including whitespace).
          - Use run_bash for things tools don't cover (grep, running tests, git, mkdir, etc.).
          - Parallelize only independent read-only calls. Run dependent or mutating calls in order.
          - Do not repeat a tool call that already succeeded.
          - Return a concise final answer when the task is complete or user input is required.

        Previous conversation and tool history:
        ----------------------------------------------------------------------
        ${history}
        ----------------------------------------------------------------------

        Current task:
        ${task}

        ${ctx.output_format}
    `
}

// ---------------------------------------------------------------------------
// Tools — each returns a plain-text result the model can read.
// ---------------------------------------------------------------------------
/// Read a UTF-8 text file and return its contents with line numbers.
function read_file(path: string) -> string {
    if (path.trim().length() == 0) {
        return "ERROR: read_file needs a `path`.";
    };
    if (!baml.fs.exists(path)) {
        return "ERROR: no such file: " + path;
    };
    let body = baml.fs.read(path);
    let numbered = with_line_numbers(body);
    "Contents of " + path + ":\n" + numbered
}

/// Create or overwrite a UTF-8 text file.
function write_file(path: string, content: string) -> string {
    if (path.trim().length() == 0) {
        return "ERROR: write_file needs a `path`.";
    };
    let n = baml.fs.write(path, content);
    `Wrote ${n} bytes to ${path}.`
}

/// Replace the first exact occurrence of old_str in a UTF-8 text file.
function edit_file(path: string, old_str: string, new_str: string) -> string {
    if (!baml.fs.exists(path)) {
        return "ERROR: no such file: " + path;
    };
    let original = baml.fs.read(path);
    if (!original.includes(old_str)) {
        return "ERROR: old_str was not found in " + path + ". Read the file again and copy the exact text.";
    };
    let updated = original.replace(old_str, new_str);
    baml.fs.write(path, updated);
    "Edited " + path + " (replaced 1 occurrence)."
}

/// List the immediate entries in a directory. Use "." for the current directory.
function list_dir(path: string) -> string {
    let dir = if (path.trim().length() == 0) {
        "."
    } else {
        path
    };
    if (!baml.fs.exists(dir)) {
        return "ERROR: no such directory: " + dir;
    };
    let entries = baml.fs.read_dir(dir);
    let lines: string[] = [];
    for (let e in entries) {
        let mark = if (e.is_dir) {
            "/"
        } else {
            ""
        };
        lines.push("  " + e.name + mark);
    }
    if (lines.length() == 0) {
        return dir + " is empty.";
    };
    "Contents of " + dir + ":\n" + lines.join("\n")
}

/// Run a shell command in the current working directory and return its output.
function run_bash(command: string) -> string {
    if (command.trim().length() == 0) {
        return "ERROR: run_bash needs a `command`.";
    };
    let out = baml.sys.shell(command, null);
    let stdout = out.stdout.to_string();
    let stderr = out.stderr.to_string();
    let header = `exit code: ${out.exit_code}`;
    let with_out = if (stdout.trim().length() > 0) {
        header + "\n--- stdout ---\n" + stdout
    } else {
        header
    };
    if (stderr.trim().length() > 0) {
        with_out + "\n--- stderr ---\n" + stderr
    } else {
        with_out
    }
}

function tool_output(output: string) -> string {
    baml.json.from_string<string>(output) catch_all (e) {
        _ => output
    }
}

function json_text(value: map<string, unknown>) -> string {
    baml.json.stringify(baml.json.to_json(value)) catch_all (e) {
        _ => "{}"
    }
}

function describe_tool(name: string, args: map<string, unknown>) -> string {
    `${name} ${json_text(args)}`
}

function render_agent_event(event: ai.events.Event) -> null {
    if let message: ai.events.AssistantMessage = event {
        for (let block in message.content) {
            if let reasoning: ai.content.Reasoning = block {
                say("  " + dim(reasoning.summary) + "\n");
            };
        }
    } else if let request: ai.events.ToolRequested = event {
        say("  " + arrow(describe_tool(request.name, request.args)) + "\n");
    } else if let completed: ai.events.ToolCompleted = event {
        say(style_result(clip(tool_output(completed.output), 1200)) + "\n");
    } else if let failed: ai.events.ToolFailed = event {
        say(style_result("ERROR: " + failed.message) + "\n");
    };
    null
}

function on_agent_event(event: ai.events.Event) -> null throws never {
    render_agent_event(event) catch_all (e) {
        _ => null
    }
}

function events_transcript(events: ai.events.Event[]) -> string {
    let lines: string[] = [];
    for (let event in events) {
        if let message: ai.events.AssistantMessage = event {
            for (let block in message.content) {
                if let reasoning: ai.content.Reasoning = block {
                    lines.push("[THOUGHT] " + reasoning.summary);
                };
            }
        } else if let request: ai.events.ToolRequested = event {
            lines.push("[ACTION] " + describe_tool(request.name, request.args));
        } else if let completed: ai.events.ToolCompleted = event {
            lines.push("[RESULT]\n" + clip(tool_output(completed.output), 6000));
        } else if let failed: ai.events.ToolFailed = event {
            lines.push("[TOOL ERROR] " + failed.message);
        } else if let feedback: ai.events.UserMessage = event {
            lines.push("[SYSTEM FEEDBACK] " + feedback.content);
        };
    }
    if (lines.length() == 0) {
        ""
    } else {
        lines.join("\n") + "\n"
    }
}

function agent_steps(events: ai.events.Event[]) -> int {
    let model_turns = 0;
    let repair_requests = 0;
    for (let event in events) {
        if (event is ai.events.AssistantMessage) {
            model_turns += 1;
        } else if (event is ai.events.UserMessage) {
            repair_requests += 1;
        };
    }
    model_turns - repair_requests
}

function turn_from_result(
    history: string,
    user_msg: string,
    result: ai.RunResult<AgentAnswer>,
) -> Turn {
    let answer = result.value.message;
    Turn {
        answer: answer,
        transcript: history
            + "\nUSER: "
            + user_msg
            + "\n"
            + events_transcript(result.journal.entries())
            + "ASSISTANT: "
            + answer
            + "\n",
        steps: agent_steps(result.journal.entries()),
        interrupted: false,
        queued: [],
    }
}

function run_turn(history: string, user_msg: string) -> Turn {
    let runner = ai.Agent<AgentAnswer>.new(
        max_steps = 30,
        tool_errors = ai.tools.ErrorMode.Report,
        on_event = on_agent_event,
    );
    let result = runner.run(code@spec(history = history, task = user_msg));
    let turn = turn_from_result(history, user_msg, result);
    say("\n" + style_assistant(turn.answer) + "\n");
    turn
}

// Build the Turn returned when a turn is cancelled, and tell the user.
function interrupt_turn(transcript: string, steps: int) -> Turn {
    let note = "⨂ interrupted.";
    say("\n" + root.ansi.yellow(note) + "\n");
    Turn {
        answer: note,
        transcript: transcript + "[INTERRUPTED by user]\n",
        steps: steps,
        interrupted: true,
        queued: [],
    }
}

// Peek at stdin (non-blocking, ~0.1s) for input. Esc + enter cancels the
// turn; any other line is staged to run after it.
function poll_interrupt() -> Interrupt {
    let out = baml.sys.shell("IFS= read -r -t 0.1 __l; rc=$?; printf '%s' \"$__l\"; exit $rc", null);
    if (out.exit_code != 0) {
        return Interrupt { cancel: false, queued: "" };
    };
    classify_interrupt(out.stdout.to_string())
}

// Classify a line typed during a turn: esc + enter (the line carries the raw
// ESC byte — trim() leaves it intact) cancels the turn; any other text is
// staged to run after it. A bare empty enter is ignored.
function classify_interrupt(raw: string) -> Interrupt {
    let line = raw.trim();
    if (line.includes(root.ansi.esc())) {
        Interrupt { cancel: true, queued: "" }
    } else {
        Interrupt { cancel: false, queued: line }
    }
}

// Run one turn concurrently and watch stdin. The agent turn runs in a spawned
// task (true parallelism — its blocking LLM/tool calls run alongside us),
// while we poll stdin. Pressing esc + enter cancels the future *mid-step* —
// even during an in-flight LLM call; any other line queues to run after the
// turn (returned on Turn.queued) without disturbing it.
function run_supervised(history: string, msg: string) -> Turn {
    let fut = spawn { run_turn(history, msg) };

    let cancelled = false;
    let queued: string[] = [];
    let watching = true;
    while (watching) {
        if (fut.is_settled()) {
            watching = false;
        } else {
            let probe = poll_interrupt();
            if (probe.cancel) {
                fut.cancel();
                cancelled = true;
                watching = false;
            } else if (probe.queued.length() > 0) {
                queued.push(probe.queued);
                say(
                    "\n  "
                        + root.ansi.yellow(
                            `✚ queued for after this turn (${queued.length()} waiting): ${probe.queued}`,
                        )
                        + "\n",
                );
            };
        };
    }

    let turn = if (cancelled) {
        interrupt_turn(history, 0)
    } else {
        (await fut) catch (e) {
            _ => {
                Turn {
                    answer: "(the turn failed — see the error above)",
                    transcript: history + "\n[turn errored]\n",
                    steps: 0,
                    interrupted: false,
                    queued: [],
                }
            }
        }
    };
    Turn {
        answer: turn.answer,
        transcript: turn.transcript,
        steps: turn.steps,
        interrupted: turn.interrupted,
        queued: queued,
    }
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

// Interactive REPL. Run with: baml run agent.main
//
// The message queue is just an in-memory array of strings, owned by this loop.
// Stage messages with /queue, then run them in order. (You can also type-ahead
// while a turn runs — the terminal buffers your keystrokes, and the next
// read_line picks each line up as its own turn. No queue file involved.)
function main() -> string {
    say(banner());
    let history = "";
    let queue: string[] = [];
    let running = true;

    while (running) {
        say(prompt_label(queue));
        let line = read_line();
        if (line.eof) {
            say("\n");
            running = false;
        } else {
            let msg = line.text.trim();
            if (msg == "exit" || msg == "quit" || msg == "/exit") {
                running = false;
            } else if (msg == "/queue" || msg == "/q") {
                say(show_queue(queue));
            } else if (msg == "/clear") {
                queue = [];
                say("  queue cleared.\n");
            } else if (msg.starts_with("/queue ") || msg.starts_with("/q ")) {
                queue.push(command_arg(msg));
                say(
                    `  ✚ queued — ${queue.length()} waiting. Queue more, or press enter to run them.\n`,
                );
            } else if (msg.length() == 0) {
                // Empty line = "run whatever is queued now".
                if (queue.length() == 0) {
                    say("  (nothing queued)\n");
                } else {
                    history = run_queue(history, queue);
                    queue = [];
                };
            } else {
                // Run the typed task now, then drain anything staged with /queue
                // or typed while it ran. (Press esc + enter mid-turn to cancel;
                //  any other typed line queues to run after the turn.)
                let turn = run_supervised(history, msg);
                history = turn.transcript;
                for (let q in turn.queued) {
                    queue.push(q);
                }
                // If the user cancelled, leave the staged queue for later.
                if (!turn.interrupted && queue.length() > 0) {
                    history = run_queue(history, queue);
                    queue = [];
                };
            };
        };
    }

    say("\nbye 👋\n");
    "session ended"
}

// Run every queued message in order, threading history through each turn.
// Lines typed while a queued turn runs join the back of the same batch.
function run_queue(history: string, queue: string[]) -> string {
    let h = history;
    let i = 0;
    while (i < queue.length()) {
        let m = queue[i];
        i = i + 1;
        say(root.ansi.magenta(`\n◆ queued (${i}/${queue.length()}) › ${m}`) + "\n");
        let t = run_supervised(h, m);
        h = t.transcript;
        for (let q in t.queued) {
            queue.push(q);
        }
        if (t.interrupted) {
            let left = queue.length() - i;
            say(root.ansi.yellow(`⨂ cancelled — skipped ${left} queued message(s).`) + "\n");
            return h;
        };
    }
    h
}

// One-shot mode for scripting/tests. Returns just the final answer.
// baml run agent.ask --json-args '{"task": "..."}'
function ask(task: string) -> string {
    let turn = run_turn("", task);
    turn.answer
}

// ---------------------------------------------------------------------------
// In-memory queue helpers
// ---------------------------------------------------------------------------

// The prompt, annotated with how many messages are staged.
function prompt_label(queue: string[]) -> string {
    if (queue.length() > 0) {
        "\n"
            + root.ansi.bold("you")
            + root.ansi.gray(` (${queue.length()} queued)`)
            + root.ansi.bold(" › ")
    } else {
        "\n" + root.ansi.bold("you › ")
    }
}

// Pretty-print the staged queue.
function show_queue(queue: string[]) -> string {
    if (queue.length() == 0) {
        "  (queue empty)\n"
    } else {
        let lines: string[] = [];
        let i = 0;
        for (let m in queue) {
            i = i + 1;
            lines.push("  " + root.ansi.cyan(`${i}.`) + " " + m);
        }
        root.ansi.gray("  queued messages:") + "\n" + lines.join("\n") + "\n"
    }
}

// Strip the leading /queue or /q token from a command line.
function command_arg(msg: string) -> string {
    if (msg.starts_with("/queue ")) {
        msg.substring(7, msg.length()).trim()
    } else if (msg.starts_with("/q ")) {
        msg.substring(3, msg.length()).trim()
    } else {
        msg.trim()
    }
}

// ---------------------------------------------------------------------------
// Terminal I/O + presentation helpers
// ---------------------------------------------------------------------------
class Line {
    text: string,
    eof: bool,
}

// Read one line from the terminal (inherited stdin). eof=true at end of input.
function read_line() -> Line {
    let out = baml.sys.shell("IFS= read -r __l; rc=$?; printf '%s' \"$__l\"; exit $rc", null);
    Line { text: out.stdout.to_string(), eof: out.exit_code != 0 }
}

// Write directly to the controlling terminal so output streams live
// (baml captures normal stdout, so we bypass it via /dev/tty).
function say(text: string) -> void {
    let opts = baml.sys.ProcessOptions { cwd: null, env: null, timeout_ms: null, stdin: text };
    baml.sys.shell("cat > /dev/tty 2>/dev/null", opts);
}

function banner() -> string {
    root.ansi.cyan(
        "\n  ┌────────────────────────────────────────────┐\n"
            + "  │   bamlcode · a tiny Claude Code, in BAML     │\n"
            + "  └────────────────────────────────────────────┘\n",
    )
        + root.ansi.gray("  Ask me to read, edit, or build code in this dir.\n\n")
        + "  "
        + root.ansi.yellow("type a task")
        + root.ansi.gray("       run it now\n")
        + "  "
        + root.ansi.yellow("/queue <task>")
        + root.ansi.gray("     stage a task (then enter to run)\n")
        + "  "
        + root.ansi.yellow("/queue")
        + root.ansi.gray("            show the queue   ")
        + root.ansi.yellow("/clear")
        + root.ansi.gray("  empty it\n")
        + "  "
        + root.ansi.yellow("enter")
        + root.ansi.gray("             run the queue now\n")
        + "  "
        + root.ansi.yellow("exit")
        + root.ansi.gray("              quit\n\n")
        + root.ansi.gray("  while I'm working, press ")
        + root.ansi.yellow("esc + enter")
        + root.ansi.gray(" to stop — or type a new task to queue it for after.\n")
}

function style_assistant(msg: string) -> string {
    root.ansi.bold(root.ansi.green("● bamlcode")) + "\n" + indent(msg)
}

// A dim "· thought" line.
function dim(s: string) -> string {
    root.ansi.gray("· " + s)
}

// A cyan "→ tool call" line.
function arrow(s: string) -> string {
    root.ansi.cyan("→ " + s)
}

// Tool result: dim by default, red when it's an error.
function style_result(result: string) -> string {
    let body = indent(result);
    if (result.starts_with("ERROR")) {
        root.ansi.red(body)
    } else {
        root.ansi.gray(body)
    }
}

function indent(s: string) -> string {
    let lines = s.lines();
    let out: string[] = [];
    for (let l in lines) {
        out.push("    " + l);
    }
    out.join("\n")
}

function with_line_numbers(body: string) -> string {
    let lines = body.lines();
    let out: string[] = [];
    let i = 0;
    for (let l in lines) {
        i = i + 1;
        out.push(`${i}\t${l}`);
    }
    out.join("\n")
}

function clip(text: string, n: int) -> string {
    if (text.length() > n) {
        text.substring(0, n) + `\n… (${text.length() - n} more chars truncated)`
    } else {
        text
    }
}
