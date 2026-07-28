// Memory for bamlcode — the file system *is* the memory layer.
//
// Every memory is one small markdown file in a memory directory:
//
//     .bamlcode/memory/prefers-uv.md
//     ---
//     name: prefers-uv
//     keywords: python, deps, install
//     ---
//     The user installs Python deps with `uv add`, never pip.
//
// Recall is automatic: before each turn the agent scores every stored memory
// against the user's message and injects only the relevant ones into the
// transcript (see `Store.inject`).
//
// Writing happens outside the main agent entirely — the supervisor hands the
// finished turn to a separate curator agent with its own context window, which
// decides what to keep (see curator.baml). The main agent's context is only
// ever *read into*, never spent on bookkeeping.

// ---------------------------------------------------------------------------
// A single memory.
// ---------------------------------------------------------------------------
class Memory {
    // Stable identity — also the file name (slugified).
    name: string,
    // Retrieval hints; matched with extra weight against the user's message.
    keywords: string[],
    // The fact itself.
    body: string,

    // How well this memory matches a tokenized query. 0 = irrelevant.
    // Name + keyword hits count triple; body hits count once.
    function score(self, tokens: string[]) -> int {
        let keys = tokenize(`${self.name} ${self.keywords.join(" ")}`);
        let body = tokenize(self.body);
        let total = 0;
        for (let t in tokens) {
            if (
                keys.some((k) -> {
                    token_matches(k, t)
                })
            ) {
                total = total + 3;
            };
            if (
                body.some((w) -> {
                    token_matches(w, t)
                })
            ) {
                total = total + 1;
            };
        }
        total
    }

    // The tag that identifies this memory inside a transcript. Injection is
    // idempotent because we skip any memory whose marker is already there.
    function marker(self) -> string {
        `[memory:${self.name}]`
    }

    // How the memory appears in the model's context.
    function render(self) -> string {
        let keys = if (self.keywords.length() > 0) {
            ` (${self.keywords.join(", ")})`
        } else {
            ""
        };
        `${self.marker()}${keys} ${self.body}`
    }

    // On-disk representation: `---` header + body.
    function to_file(self) -> string {
        // NB: a trailing \n before the closing backtick is swallowed by the lexer,
        // so the final newline is concatenated on.
        `---\nname: ${self.name}\nkeywords: ${self.keywords.join(", ")}\n---\n${self.body}` + "\n"
    }
}

// The block injected into a turn, plus which memories it carried.
class Recall {
    block: string,
    names: string[],
}

// ---------------------------------------------------------------------------
// The store: a directory of memory files.
//
// Everything is scoped to `dir`, so tests point at a temp directory and the
// agent points at `.bamlcode/memory` (or $BAMLCODE_MEMORY_DIR).
// ---------------------------------------------------------------------------
class Store {
    dir: string,

    function ensure(self) -> void {
        if (!baml.fs.exists(self.dir)) {
            baml.fs.mkdir(self.dir, baml.fs.MkdirOptions { recursive: true });
        };
    }

    function path_for(self, name: string) -> string {
        `${self.dir}/${slugify(name)}.md`
    }

    // Write (or overwrite) a memory. Returns the stored value.
    function remember(self, name: string, keywords: string[], body: string) -> Memory {
        //# persist one fact to disk
        self.ensure();
        let m = Memory { name: slugify(name), keywords: normalize_keywords(keywords), body: body.trim() };
        baml.fs.write(self.path_for(m.name), m.to_file());
        m
    }

    function get(self, name: string) -> Memory? {
        let path = self.path_for(name);
        if (!baml.fs.exists(path)) {
            return null;
        };
        parse_memory(slugify(name), baml.fs.read(path))
    }

    // Delete a memory. Returns false if it wasn't there.
    function forget(self, name: string) -> bool {
        let path = self.path_for(name);
        if (!baml.fs.exists(path)) {
            return false;
        };
        baml.fs.remove(path);
        true
    }

    // Every memory on disk, in directory order.
    function all(self) -> Memory[] {
        if (!baml.fs.exists(self.dir)) {
            return [];
        };
        let out: Memory[] = [];
        for (let e in baml.fs.read_dir(self.dir)) {
            if (e.is_file && e.name.ends_with(".md")) {
                let slug = e.name.substring(0, e.name.length() - 3);
                out.push(parse_memory(slug, baml.fs.read(`${self.dir}/${e.name}`)));
            };
        }
        out
    }

    // The relevant memories for a query, best match first.
    function search(self, query: string, limit: int = 3) -> Memory[] {
        //# score every memory against the message
        let tokens = tokenize(query);
        if (tokens.length() == 0) {
            return [];
        };
        let hits = self.all().filter((m) -> {
            m.score(tokens) > 0
        });
        hits.sort_by_key((m) -> {
            0 - m.score(tokens)
        });
        hits.slice(0, min_int(limit, hits.length()))
    }

    // The automatic-injection entry point.
    //
    // Returns the context block to prepend to a turn — empty when nothing is
    // relevant, and skipping anything already present in `history` so a long
    // session never re-injects the same fact.
    function inject(self, query: string, history: string, limit: int = 3) -> Recall {
        //# recall what's relevant, skip what's already in context
        let fresh = self.search(query, limit = limit).filter((m) -> {
            !history.includes(m.marker())
        });
        if (fresh.length() == 0) {
            return Recall { block: "", names: [] };
        };
        let lines = fresh.map((m) -> {
            m.render()
        });
        Recall {
            block: `\n[RECALLED MEMORY — durable facts from earlier sessions; trust them unless the user contradicts them]\n${lines.join("\n")}`
                + "\n",
            names: fresh.map((m) -> {
                m.name
            }),
        }
    }

    // A compact catalogue of everything stored — what the curator sees so it
    // can correct or delete an existing memory instead of duplicating it.
    function index(self) -> string {
        let memories = self.all();
        if (memories.length() == 0) {
            return "(memory is empty)";
        };
        memories
            .map((m) -> {
                `- ${m.name} (${m.keywords.join(", ")}): ${m.body}`
            })
            .join("\n")
    }

    // A human-readable listing for the `/memory` REPL command.
    function listing(self) -> string {
        let memories = self.all();
        if (memories.length() == 0) {
            return `  (no memories yet — stored under ${self.dir}/)` + "\n";
        };
        let lines = memories.map((m) -> {
            `  • ${m.name} (${m.keywords.join(", ")})\n    ${m.body}`
        });
        `  ${memories.length()} memor${plural(memories.length())} in ${self.dir}/\n${lines.join("\n")}`
            + "\n"
    }
}

// The store the agent uses. Override the location with $BAMLCODE_MEMORY_DIR.
function store() -> Store {
    Store { dir: baml.env.get("BAMLCODE_MEMORY_DIR") ?? ".bamlcode/memory" }
}

// Memory is on unless you turn it off: BAMLCODE_MEMORY=off disables both
// recall and curation (handy for demos, benchmarks, and one-shot runs).
function enabled() -> bool {
    (baml.env.get("BAMLCODE_MEMORY") ?? "on").trim().to_lower_case() != "off"
}

// ---------------------------------------------------------------------------
// Parsing / formatting
// ---------------------------------------------------------------------------

// Read a memory file. Files without a `---` header are treated as a bare body,
// so hand-written notes dropped into the directory still work.
function parse_memory(slug: string, raw: string) -> Memory {
    let lines = raw.lines();
    if ((lines.at(0) ?? "").trim() != "---") {
        return Memory { name: slug, keywords: [], body: raw.trim() };
    };
    let name = slug;
    let keywords: string[] = [];
    let body: string[] = [];
    let in_header = true;
    let i = 1;
    while (i < lines.length()) {
        let line = lines[i];
        i = i + 1;
        if (in_header) {
            if (line.trim() == "---") {
                in_header = false;
            } else if (line.starts_with("name:")) {
                let v = header_value(line, "name:");
                if (v.length() > 0) {
                    name = v;
                };
            } else if (line.starts_with("keywords:")) {
                keywords = split_keywords(header_value(line, "keywords:"));
            };
        } else {
            body.push(line);
        };
    }
    Memory { name: name, keywords: keywords, body: body.join("\n").trim() }
}

function header_value(line: string, key: string) -> string {
    line.substring(key.length(), line.length()).trim()
}

function split_keywords(raw: string) -> string[] {
    normalize_keywords(raw.split(","))
}

function normalize_keywords(raw: string[]) -> string[] {
    raw.map((k) -> {
            k.trim().to_lower_case()
        })
        .filter((k) -> {
            k.length() > 0
        })
}

// File-safe, stable id: lowercase alphanumerics, everything else a dash.
function slugify(name: string) -> string {
    let out = "";
    for (let ch in name.to_lower_case().chars()) {
        if (ch.is_ascii_alphanumeric()) {
            out = out + ch;
        } else if (out.length() > 0 && !out.ends_with("-")) {
            out = out + "-";
        };
    }
    let trimmed = if (out.ends_with("-")) {
        out.substring(0, out.length() - 1)
    } else {
        out
    };
    if (trimmed.length() == 0) {
        "memory"
    } else {
        trimmed
    }
}

// ---------------------------------------------------------------------------
// Retrieval helpers
// ---------------------------------------------------------------------------

// Words worth matching on: lowercase, alphanumeric, 2+ chars, not a stopword.
function tokenize(text: string) -> string[] {
    let out: string[] = [];
    let current = "";
    for (let ch in text.to_lower_case().chars()) {
        if (ch.is_ascii_alphanumeric()) {
            current = current + ch;
        } else {
            if (keep_token(current)) {
                out.push(current);
            };
            current = "";
        };
    }
    if (keep_token(current)) {
        out.push(current);
    };
    out
}

function keep_token(t: string) -> bool {
    t.length() >= 2 && !stopwords().includes(t)
}

// Two-letter tokens are kept (uv, ci, db, go are all real signals), so the
// stopword list carries the short filler words too.
function stopwords() -> string[] {
    [
        "am",
        "an",
        "as",
        "at",
        "be",
        "by",
        "do",
        "if",
        "in",
        "is",
        "it",
        "me",
        "my",
        "no",
        "of",
        "on",
        "or",
        "so",
        "to",
        "up",
        "us",
        "we",
        "the",
        "and",
        "for",
        "you",
        "your",
        "our",
        "with",
        "that",
        "this",
        "from",
        "have",
        "has",
        "are",
        "was",
        "were",
        "can",
        "will",
        "how",
        "what",
        "when",
        "why",
        "who",
        "all",
        "any",
        "but",
        "not",
        "get",
        "got",
        "let",
        "use",
        "into",
        "onto",
        "its",
        "his",
        "her",
        "them",
        "they",
        "than",
        "then",
        "there",
        "here",
        "some",
        "just",
        "like",
        "make",
        "made",
        "does",
        "did",
    ]
}

// Two words match if they're equal, or if one is a prefix of the other and the
// shorter is at least 4 chars — so "test"/"tests" match but "dep"/"deploy"
// (and "python"/"pytest") stay apart.
function token_matches(a: string, b: string) -> bool {
    if (a == b) {
        return true;
    };
    let shorter = if (a.length() < b.length()) {
        a
    } else {
        b
    };
    let longer = if (a.length() < b.length()) {
        b
    } else {
        a
    };
    shorter.length() >= 4 && longer.starts_with(shorter)
}

function min_int(a: int, b: int) -> int {
    if (a < b) {
        a
    } else {
        b
    }
}

function plural(n: int) -> string {
    if (n == 1) {
        "y"
    } else {
        "ies"
    }
}
