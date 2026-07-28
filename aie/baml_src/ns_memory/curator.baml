// The curator — memory's *write* side, run by the supervisor after a turn.
//
// The main agent never writes memory. It has no remember/forget tools, and its
// prompt says nothing about how memory is stored. Instead the supervisor hands
// the finished turn to this second, tiny agent, which runs in its own context
// window and decides what (if anything) is worth keeping. The main agent's
// context only ever *receives* memory (see `Store.inject`).

// A cheap, fast model — curation is a small classification job, not reasoning.
client<llm> Curator {
    provider: anthropic,
    options: {
        model: "claude-haiku-4-5-20251001",
        api_key: env.ANTHROPIC_API_KEY,
        max_tokens: 1024,
    },
}

class MemoryEdit {
    op: "save" | "delete",
    name: string @description(
        "short kebab-case id, e.g. \"test-command\". Re-use an existing name to correct it.",
    ),
    keywords: string[] @description("words a future question about this fact would use. Empty for delete."),
    body: string @description("one or two sentences stating the fact. Empty for delete."),
}

// At most this many memory writes per turn — a runaway curator can't flood the
// store (or the next turn's context).
function max_edits_per_turn() -> int {
    5
}

// Decide what to remember from one finished turn. Returns [] most of the time.
function curate(turn: string, index: string) -> MemoryEdit[] {
    client: Curator
    prompt: #"
        You maintain the long-term memory of a coding agent. You are NOT the coding agent —
        you only read what just happened and decide what is worth keeping for future sessions.

        Save a fact ONLY if it is durable and would change how a future session behaves:
          - user preferences and working style ("uses uv, never pip")
          - project conventions and invariants ("all migrations live in db/migrations")
          - commands that are known to work ("tests: uv run pytest -q")
          - where important things live, and decisions the user made and why

        Do NOT save:
          - task state, progress, or anything about this specific turn
          - file contents, code, or anything the agent can re-read in seconds
          - secrets, tokens, passwords, or personal data
          - guesses, or anything the user did not confirm

        Use `delete` when the turn shows an existing memory is now wrong or obsolete.
        To correct a memory, `save` it under the SAME name — that overwrites it.

        Most turns are worth nothing. Returning an empty list is the common, correct answer.
        Never return more than 5 edits.

        Memories already stored:
        ----------------------------------------------------------------------
        {{ index }}
        ----------------------------------------------------------------------

        The turn that just finished:
        ----------------------------------------------------------------------
        {{ turn }}
        ----------------------------------------------------------------------

        {{ ctx.output_format }}
    "#
}

// Apply curator edits to the store. Pure plumbing — invalid edits are dropped,
// not trusted. Returns a short label per applied edit ("+name" / "-name").
function apply_edits(edits: MemoryEdit[], store: Store) -> string[] {
    //# write what the curator decided to keep
    let applied: string[] = [];
    let capped = edits.slice(0, min_int(max_edits_per_turn(), edits.length()));
    for (let e in capped) {
        match (e.op) {
            "save" => {
                if (e.name.trim().length() > 0 && e.body.trim().length() > 0) {
                    applied.push(`+${store.remember(e.name, e.keywords, e.body).name}`);
                };
            },
            "delete" => {
                if (store.forget(e.name)) {
                    applied.push(`-${slugify(e.name)}`);
                };
            },
        };
    }
    applied
}

// The supervisor's entry point: curate one finished turn, apply the result.
// Never throws — a memory failure must not take down the session.
function curate_turn(turn: string, store: Store = root.memory.store()) -> string[] {
    if (turn.trim().length() == 0) {
        return [];
    };
    apply_edits(curate(turn, store.index()), store) catch_all (e) {
        _ => []
    }
}
