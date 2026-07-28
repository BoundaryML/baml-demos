// Deterministic tests for the file-system memory layer (no LLM calls).
//
//   baml test -i "memory-store::"      run just the store tests
//   baml test --list                   see every selector

// A store pointed at an empty temp directory, wiped between runs.
function fresh_store(case: string) -> Store {
    let s = Store { dir: `/tmp/bamlcode_memory_test/${case}` };
    if (baml.fs.exists(s.dir)) {
        baml.fs.remove_dir_all(s.dir);
    };
    s.ensure();
    s
}

testset "memory-text" {
    // names become file-safe slugs.
    test "slugify_makes_file_safe_names" {
        assert.equal(slugify("Prefers UV"), "prefers-uv");
        assert.equal(slugify("  deploy/  staging!! "), "deploy-staging");
        assert.equal(slugify("!!!"), "memory")
    }

    // tokenize drops stopwords, single letters, and punctuation — but keeps
    // short, meaningful tool names like `uv`.
    test "tokenize_keeps_meaningful_words" {
        assert.equal(tokenize("How do I run the tests?"), ["run", "tests"]);
        assert.equal(tokenize("uv add pydantic"), ["uv", "add", "pydantic"]);
        assert.equal(tokenize("   "), [])
    }

    // matching tolerates plurals but not accidental prefixes.
    test "token_matching_is_prefix_not_substring" {
        assert.is_true(token_matches("test", "tests"));
        assert.is_true(token_matches("deploy", "deploy"));
        assert.is_true(!token_matches("dep", "deploy"));
        assert.is_true(!token_matches("python", "pytest"))
    }

    // keywords are lowercased, trimmed, and blanks dropped.
    test "keywords_are_normalized" {
        assert.equal(split_keywords(" Python , DEPS,, install "), ["python", "deps", "install"])
    }

    // a file with a `---` header round-trips through to_file/parse_memory.
    test "file_format_round_trips" {
        let m = Memory { name: "prefers-uv", keywords: ["python", "deps"], body: "Use `uv add`." };
        let back = parse_memory("ignored-slug", m.to_file());
        assert.equal(back.name, "prefers-uv");
        assert.equal(back.keywords, ["python", "deps"]);
        assert.equal(back.body, "Use `uv add`.")
    }

    // a hand-written note with no header still parses — the file name is the id.
    test "headerless_file_is_a_bare_body" {
        let m = parse_memory("scratch", "just a note\nsecond line\n");
        assert.equal(m.name, "scratch");
        assert.equal(m.keywords, []);
        assert.equal(m.body, "just a note\nsecond line")
    }

    // multi-line bodies survive the header parser.
    test "multiline_body_is_preserved" {
        let m = parse_memory("x", "---\nname: build\nkeywords: ci\n---\nline one\n\nline three\n");
        assert.equal(m.body, "line one\n\nline three")
    }
}

testset "memory-store" {
    // remember → get round-trips through a real file on disk.
    test "remember_then_get" {
        let s = fresh_store("round_trip");
        s.remember("Prefers UV", ["Python", "deps"], "  The user installs deps with `uv add`.  ");

        let got = s.get("prefers-uv");
        assert.not_null(got);
        assert.equal(got?.name, "prefers-uv");
        assert.equal(got?.keywords, ["python", "deps"]);
        assert.equal(got?.body, "The user installs deps with `uv add`.");

        // the memory really is a file, and it's readable by a human.
        let raw = baml.fs.read(s.path_for("Prefers UV"));
        assert.contains(raw, "name: prefers-uv");
        assert.contains(raw, "keywords: python, deps");
        assert.is_true(raw.ends_with("\n"))
    }

    // the display name and the lookup key agree, whatever casing you use.
    test "lookup_is_slug_insensitive" {
        let s = fresh_store("slug_lookup");
        s.remember("Deploy Steps", [], "run ./deploy.sh");
        assert.not_null(s.get("deploy steps"));
        assert.not_null(s.get("DEPLOY-STEPS"))
    }

    // remembering the same name twice overwrites instead of duplicating.
    test "remember_overwrites_same_name" {
        let s = fresh_store("overwrite");
        s.remember("port", ["server"], "the dev server runs on 3000");
        s.remember("port", ["server"], "the dev server runs on 8080");
        assert.equal(s.all().length(), 1);
        assert.equal(s.get("port")?.body, "the dev server runs on 8080")
    }

    // forget deletes the file; forgetting nothing is a false, not a crash.
    test "forget_removes_the_file" {
        let s = fresh_store("forget");
        s.remember("temp", [], "throwaway");
        assert.is_true(s.forget("temp"));
        assert.equal(s.get("temp"), null);
        assert.is_true(!s.forget("temp"))
    }

    // a note dropped into the directory by hand is picked up like any other.
    test "hand_written_file_is_discovered" {
        let s = fresh_store("hand_written");
        baml.fs.write(`${s.dir}/dropped.md`, "the staging db password is in 1password");
        assert.equal(s.all().length(), 1);
        assert.equal(s.all().at(0)?.name, "dropped")
    }

    // non-markdown files in the directory are ignored.
    test "non_md_files_are_ignored" {
        let s = fresh_store("ignore_others");
        s.remember("real", ["thing"], "a real memory");
        baml.fs.write(`${s.dir}/notes.txt`, "not a memory");
        assert.equal(s.all().length(), 1)
    }

    // an empty (or missing) store is empty, not an error.
    test "empty_store_is_empty" {
        let s = fresh_store("empty");
        assert.equal(s.all(), []);
        assert.equal(s.search("anything at all"), []);
        assert.contains(s.listing(), "no memories yet")
    }
}

// Three memories: two about python, one about deploys.
function seeded(case: string) -> Store {
    let s = fresh_store(`recall-${case}`);
    s.remember("prefers-uv", ["python", "deps"], "Install python deps with `uv add`, never pip.");
    s.remember("test-command", ["tests", "pytest"], "Run the suite with `uv run pytest -q`.");
    s.remember("deploy-steps", ["deploy", "prod"], "Deploys go out via `make ship` on Tuesdays.");
    s
}

// Two memories, for the injection tests.
function seeded_inject(case: string) -> Store {
    let s = fresh_store(`inject-${case}`);
    s.remember("prefers-uv", ["python", "deps"], "Install python deps with `uv add`, never pip.");
    s.remember("deploy-steps", ["deploy", "prod"], "Deploys go out via `make ship`.");
    s
}

// A save edit, spelled out (the curator returns these).
function save_edit(name: string, keywords: string[], body: string) -> MemoryEdit {
    MemoryEdit { op: "save", name: name, keywords: keywords, body: body }
}

function delete_edit(name: string) -> MemoryEdit {
    MemoryEdit { op: "delete", name: name, keywords: [], body: "" }
}

testset "memory-curator" {
    // save writes, delete removes — the curator's two verbs.
    test "apply_edits_saves_and_deletes" {
        let s = fresh_store("curator-apply");
        s.remember("stale", ["old"], "the port is 3000");

        let applied = apply_edits([save_edit("test-command", ["tests"], "run `uv run pytest -q`"), delete_edit("stale")], s);
        assert.equal(applied, ["+test-command", "-stale"]);
        assert.equal(s.get("test-command")?.body, "run `uv run pytest -q`");
        assert.equal(s.get("stale"), null)
    }

    // a curator that hallucinates an empty edit changes nothing.
    test "apply_edits_drops_invalid_edits" {
        let s = fresh_store("curator-invalid");
        let applied = apply_edits(
            [
                save_edit("", ["x"], "no name"),
                save_edit("no-body", ["x"], "   "),
                delete_edit("never-existed"),
            ],
            s,
        );
        assert.equal(applied, []);
        assert.equal(s.all(), [])
    }

    // saving an existing name corrects it in place instead of duplicating.
    test "apply_edits_corrects_in_place" {
        let s = fresh_store("curator-correct");
        s.remember("port", ["server"], "the dev server runs on 3000");
        apply_edits([save_edit("port", ["server"], "the dev server runs on 8080")], s);
        assert.equal(s.all().length(), 1);
        assert.equal(s.get("port")?.body, "the dev server runs on 8080")
    }

    // a runaway curator can't flood the store.
    test "apply_edits_is_capped" {
        let s = fresh_store("curator-cap");
        let edits = [
            save_edit("m1", [], "one"),
            save_edit("m2", [], "two"),
            save_edit("m3", [], "three"),
            save_edit("m4", [], "four"),
            save_edit("m5", [], "five"),
            save_edit("m6", [], "six"),
            save_edit("m7", [], "seven"),
        ];
        assert.equal(apply_edits(edits, s).length(), max_edits_per_turn());
        assert.equal(s.all().length(), max_edits_per_turn())
    }

    // the curator sees a compact catalogue so it can correct, not duplicate.
    test "index_lists_stored_facts" {
        let s = fresh_store("curator-index");
        assert.equal(s.index(), "(memory is empty)");
        s.remember("prefers-uv", ["python"], "uses uv");
        assert.equal(s.index(), "- prefers-uv (python): uses uv")
    }

    // an empty turn is never sent to the model.
    test "empty_turn_is_not_curated" {
        assert.equal(curate_turn("   ", store = fresh_store("curator-empty")), [])
    }
}

testset "memory-recall" {
    // the best match comes back first, and irrelevant memories stay out.
    test "search_ranks_relevant_first" {
        let hits = seeded("ranks").search("how do I add a python dependency?");
        assert.equal(hits.length(), 1);
        assert.equal(hits.at(0)?.name, "prefers-uv")
    }

    // keyword hits outrank body-only hits.
    test "keyword_hits_outrank_body_hits" {
        let s = fresh_store("ranking");
        s.remember("keyworded", ["deploy"], "unrelated body text");
        s.remember("body-only", ["misc"], "this body mentions deploy once");
        let hits = s.search("deploy");
        assert.equal(hits.length(), 2);
        assert.equal(hits.at(0)?.name, "keyworded")
    }

    // a query with nothing in common recalls nothing.
    test "unrelated_query_recalls_nothing" {
        assert.equal(seeded("unrelated").search("what colour is the sky").length(), 0)
    }

    // recall is capped, so a big store can't flood the prompt.
    test "search_respects_limit" {
        let s = fresh_store("limit");
        s.remember("a", ["deploy"], "one");
        s.remember("b", ["deploy"], "two");
        s.remember("c", ["deploy"], "three");
        assert.equal(s.search("deploy").length(), 3);
        assert.equal(s.search("deploy", limit = 2).length(), 2)
    }

    // stopwords alone must not drag in every memory.
    test "stopword_only_query_recalls_nothing" {
        assert.equal(seeded("stopwords").search("what is that").length(), 0)
    }
}

testset "memory-inject" {
    // a relevant message gets a labelled block carrying the fact.
    test "injects_relevant_memory" {
        let r = seeded_inject("relevant").inject("add a python dep", "");
        assert.equal(r.names, ["prefers-uv"]);
        assert.contains(r.block, "RECALLED MEMORY");
        assert.contains(r.block, "[memory:prefers-uv]");
        assert.contains(r.block, "uv add");
        // unrelated memories are not along for the ride.
        assert.is_true(!r.block.includes("make ship"))
    }

    // nothing relevant → nothing injected. The prompt stays clean.
    test "injects_nothing_when_irrelevant" {
        let r = seeded_inject("irrelevant").inject("hello there", "");
        assert.equal(r.block, "");
        assert.equal(r.names, [])
    }

    // a memory already in the transcript is not injected twice.
    test "injection_is_idempotent" {
        let s = seeded_inject("idempotent");
        let first = s.inject("add a python dep", "");
        let history = `some earlier turn${first.block}`;
        let second = s.inject("another python dep question", history);
        assert.equal(second.block, "");
        assert.equal(second.names, [])
    }

    // ...but a *different* relevant memory still gets through.
    test "new_memory_still_injects_into_used_history" {
        let s = seeded_inject("fresh-memory");
        let history = `USER: python deps${s.inject("python deps", "").block}`;
        let next = s.inject("time to deploy to prod", history);
        assert.equal(next.names, ["deploy-steps"])
    }

    // the listing renders what the store holds.
    test "listing_shows_memories" {
        let out = seeded_inject("listing").listing();
        assert.contains(out, "prefers-uv");
        assert.contains(out, "deploy-steps");
        assert.contains(out, "2 memories")
    }
}
