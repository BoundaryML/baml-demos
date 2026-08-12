// Deterministic tests for the tool layer (no LLM calls).
// Run with:  baml test            (all)
//            baml test --list      (list cases)

class FakeAgentClient {
    calls: int,

    implements ai.Client {
        function id(self) -> string {
            "fake-agent-client"
        }

        function invoke(self, input: ai.ModelTurnInput) -> ai.ModelTurn {
            self.calls += 1;
            if (self.calls == 1) {
                ai.ModelTurn {
                    content: [
                        ai.content.ToolUse {
                            id: "call-1",
                            name: "run_bash",
                            args: { "command": "printf agent-runner-ok" },
                        },
                    ],
                    stop_reason: ai.content.StopReason.ToolUse,
                    usage: null,
                }
            } else {
                ai.ModelTurn {
                    content: [ai.content.Text { text: `{ "message": "done" }` }],
                    stop_reason: ai.content.StopReason.Complete,
                    usage: null,
                }
            }
        }
    }
}

testset "tools" {
    // write → read round-trips, with line numbers added on read.
    test "write_then_read" {
        let w = write_file("/tmp/bamlcode_test/a.txt", "alpha\nbeta\n");
        assert.contains(w, "Wrote");

        let r = read_file("/tmp/bamlcode_test/a.txt");
        assert.contains(r, "1\talpha");
        assert.contains(r, "2\tbeta");
    }

    // edit replaces the first exact occurrence.
    test "edit_replaces_text" {
        write_file("/tmp/bamlcode_test/b.txt", "the quick brown fox");
        let e = edit_file("/tmp/bamlcode_test/b.txt", "brown", "lazy");
        assert.contains(e, "Edited");

        let r = read_file("/tmp/bamlcode_test/b.txt");
        assert.contains(r, "the quick lazy fox");
    }

    // edit on text that isn't present is a clear, recoverable error.
    test "edit_miss_is_error" {
        write_file("/tmp/bamlcode_test/c.txt", "hello");
        let e = edit_file("/tmp/bamlcode_test/c.txt", "NOPE", "x");
        assert.contains(e, "ERROR");
    }

    // reading a missing file is a clear error, not a crash.
    test "read_missing_is_error" {
        let r = read_file("/tmp/bamlcode_test/does_not_exist.txt");
        assert.contains(r, "ERROR");
    }

    // run_bash reports exit code and stdout.
    test "bash_reports_exit_and_stdout" {
        let r = run_bash("echo hello-bamlcode");
        assert.contains(r, "exit code: 0");
        assert.contains(r, "hello-bamlcode");
    }

    // run_bash surfaces a non-zero exit code instead of throwing.
    test "bash_reports_failure" {
        let r = run_bash("exit 3");
        assert.contains(r, "exit code: 3");
    }
}

testset "queue" {
    // /queue and /q prefixes are stripped to the bare message.
    test "command_arg_strips_prefix" {
        assert.equal(command_arg("/queue fix the bug"), "fix the bug");
        assert.equal(command_arg("/q add tests"), "add tests");
    }

    // show_queue numbers the staged messages in order.
    test "show_queue_lists_items" {
        let q = ["first", "second"];
        let out = show_queue(q);
        // color-agnostic: numbering and message text appear (ANSI codes may sit between them)
        assert.contains(out, "1.");
        assert.contains(out, "first");
        assert.contains(out, "2.");
        assert.contains(out, "second");
    }

    // an empty queue renders as empty.
    test "show_queue_empty" {
        let empty: string[] = [];
        assert.contains(show_queue(empty), "empty");
    }

    // the prompt advertises how many messages are staged.
    test "prompt_label_shows_count" {
        assert.contains(prompt_label(["a", "b", "c"]), "3 queued");
        let none: string[] = [];
        assert.contains(prompt_label(none), "you ›");
    }
}

testset "interrupt" {
    // esc + enter (a line carrying the raw ESC byte) cancels the turn.
    test "esc_enter_cancels" {
        let i = classify_interrupt(string.from_code_points([27]));
        assert.is_true(i.cancel);
        assert.equal(i.queued, "");
    }

    // a bare empty enter is ignored — nothing cancelled, nothing queued.
    test "empty_line_is_ignored" {
        let i = classify_interrupt("   ");
        assert.is_true(!i.cancel);
        assert.equal(i.queued, "");
    }

    // any other text (even the old cancel words) queues to run after the
    // current turn instead of interrupting it.
    test "other_text_queues" {
        let i = classify_interrupt("also write docs");
        assert.is_true(!i.cancel);
        assert.equal(i.queued, "also write docs");
        assert.equal(classify_interrupt("cancel").queued, "cancel");
    }
}

testset "agent" {
    test "runner_calls_tool_and_parses_final_answer" {
        let fake = FakeAgentClient { calls: 0 };
        let runner = ai.Agent<AgentAnswer>.new(max_steps = 3, client = fake);
        let result = runner.run(code@spec(history = "", task = "test"));
        assert.equal(result.value.message, "done");
        assert.equal(fake.calls, 2);
        assert.contains(events_transcript(result.journal.entries()), "agent-runner-ok");
    }

    test "spec_registers_tools" {
        let tools = code@spec(history = "", task = "test").tools().list();
        assert.equal(tools.length(), 5);
        assert.equal(
            tools.map((tool) -> {
                tool.name
            }),
            ["read_file", "write_file", "edit_file", "list_dir", "run_bash"],
        );
        assert.is_true(
            tools.every((tool) -> {
                tool.description.length() > 0
            }),
        );
    }

    test "journal_becomes_next_turn_history" {
        let events: ai.events.Event[] = [
            ai.events.RunStarted { spec_name: "code", arguments: {} },
            ai.events.AssistantMessage {
                content: [
                    ai.content.Reasoning { summary: "Inspect the repository." },
                    ai.content.ToolUse { id: "1", name: "list_dir", args: { "path": "." } },
                ],
                client_id: "test",
            },
            ai.events.ToolRequested { id: "1", name: "list_dir", args: { "path": "." } },
            ai.events.ToolCompleted { id: "1", output: baml.json.to_string("Contents of .") },
            ai.events.UserMessage { content: "Return valid output." },
            ai.events.AssistantMessage {
                content: [ai.content.Text { text: "done" }],
                client_id: "test",
            },
            ai.events.FinalProduced { value_json: `{ "message": "done" }` },
        ];
        let transcript = events_transcript(events);
        assert.contains(transcript, "[THOUGHT] Inspect the repository.");
        assert.contains(transcript, `[ACTION] list_dir {"path":"."}`);
        assert.contains(transcript, "[RESULT]\nContents of .");
        assert.contains(transcript, "[SYSTEM FEEDBACK] Return valid output.");
        assert.equal(agent_steps(events), 1);
    }

    test "run_result_becomes_turn" {
        let events: ai.events.Event[] = [
            ai.events.RunStarted { spec_name: "code", arguments: {} },
            ai.events.AssistantMessage {
                content: [ai.content.Text { text: "done" }],
                client_id: "test",
            },
            ai.events.FinalProduced { value_json: `{ "message": "done" }` },
        ];
        let result = ai.RunResult<AgentAnswer> {
            value: AgentAnswer { message: "done" },
            journal: ai.Journal { log: events },
            usage: ai.events.Usage {
                input_tokens: 1,
                output_tokens: 1,
                cached_input_tokens: null,
                reasoning_tokens: null,
            },
        };
        let turn = turn_from_result("earlier\n", "finish", result);
        assert.equal(turn.answer, "done");
        assert.equal(turn.steps, 1);
        assert.contains(turn.transcript, "earlier\n\nUSER: finish");
        assert.contains(turn.transcript, "ASSISTANT: done");
    }
}
