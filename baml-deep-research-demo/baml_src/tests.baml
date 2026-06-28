// Pure unit tests for the deterministic orchestration/post-processing.
// NOTE: these call NO LLM functions — they exercise pure BAML logic on literal data
// so they run offline with no API keys.

function make_result(title: string, url: string, content: string) -> SearchResult {
    SearchResult { title: title, url: url, content: content }
}

function make_learning(text: string, follow_ups: string[], source: string) -> Learning {
    Learning { learning: text, follow_up_questions: follow_ups, source: source }
}

test "collect_follow_ups dedups and drops empties" {
    let learnings = [
        make_learning("a", ["What is X?"], "u1"),
        make_learning("b", ["What is Y?"], "u2"),
        make_learning("c", ["What is X?"], "u3"),
        make_learning("d", [""], "u4"),
        make_learning("e", [], "u5"),
    ];
    let qs = collect_follow_ups(learnings);
    assert.equal(qs, ["What is X?", "What is Y?"])
}

test "merge_research concatenates all parts and sets phase" {
    let p1 = ResearchData {
        queries: ["q1"],
        search_results: [make_result("t1", "u1", "c1")],
        learnings: [make_learning("l1", ["f1"], "u1")],
        completed_queries: ["q1"],
        phase: "initial",
    };
    let p2 = ResearchData {
        queries: ["q2"],
        search_results: [make_result("t2", "u2", "c2")],
        learnings: [make_learning("l2", [], "u2")],
        completed_queries: ["q2"],
        phase: "initial",
    };
    let merged = merge_research([p1, p2], "follow-up");
    assert.equal(merged.queries, ["q1", "q2"]);
    assert.equal(merged.completed_queries, ["q1", "q2"]);
    assert.equal(merged.search_results.length(), 2);
    assert.equal(merged.learnings.length(), 2);
    assert.equal(merged.phase, "follow-up")
}

// Pure model of the dedup-by-url logic used inside research_one_query: a URL already in
// `seen` is never accepted twice.
function accept_urls(seen: string[], urls: string[]) -> string[] {
    let kept: string[] = [];
    for (let u in urls) {
        if (!seen.includes(u)) {
            seen.push(u);
            kept.push(u);
        }
    }
    kept
}

test "dedup by url drops already-seen urls" {
    let seen: string[] = ["http://a"];
    let kept = accept_urls(seen, ["http://a", "http://b", "http://b", "http://c"]);
    assert.equal(kept, ["http://b", "http://c"]);
    assert.equal(seen, ["http://a", "http://b", "http://c"])
}
