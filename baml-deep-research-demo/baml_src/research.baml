// Research LLM functions + the deterministic 2-phase orchestration.
// Ports evaluationAgent + evaluateResultTool, learningExtractionAgent +
// extractLearningsTool, and researchAgent + researchWorkflow's research step.

// Ports evaluationAgent + evaluateResultTool: is this result relevant to the query?
function evaluate_result(query: string, result: SearchResult) -> Evaluation {
    client: Smart
    prompt: `
        You are an expert evaluation agent. Determine whether a search result is relevant
        to a research query.

        Evaluation criteria:
        - Does the content directly relate to the query topic?
        - Does it provide useful information that would help answer the query?
        - Is the source credible and authoritative?
        - Is the information current and accurate?

        Be strict but fair. Only mark a result relevant if it genuinely contributes to answering the query.

        Research query: "${query}"

        Search result:
        Title: ${result.title}
        URL: ${result.url}
        Content snippet: ${result.content.substring(0, 500)}

        ${ctx.output_format}
    `
}

// Ports learningExtractionAgent + extractLearningsTool: extract one key learning
// plus up to one focused follow-up question.
function extract_learnings(query: string, result: SearchResult) -> Learning {
    client: Smart
    prompt: `
        You are an expert at analyzing search results and extracting key insights.

        1. Extract the single most important, specific, actionable learning from the content.
        2. Generate at most 1 focused follow-up question that would deepen the research.
        3. Set source to the result's URL.

        The user is researching "${query}".

        Title: ${result.title}
        URL: ${result.url}
        Content: ${result.content.substring(0, 1500)}

        ${ctx.output_format}
    `
}

// Generates the focused initial queries the Mastra researchAgent would produce via
// tool-calling. (PHASE 1, step 1: "Break down the main topic into 2 specific queries".)
function plan_research_queries(topic: string, count: int = 2) -> string[] {
    client: Planner
    prompt: `
        You are an expert research agent. Break the main research topic into ${count} specific,
        focused search queries. Keep queries focused and specific — avoid overly general queries.

        Topic: "${topic}"

        Return exactly ${count} search query strings.

        ${ctx.output_format}
    `
}

// A search result paired with its relevance evaluation.
class EvaluatedResult {
    result: SearchResult,
    evaluation: Evaluation,
}

// evaluate_result with the evaluateResultTool try/catch fallback: any failure
// (bad LLM response, parse error) degrades to "not relevant" instead of aborting.
function safe_evaluate(query: string, result: SearchResult) -> Evaluation {
    evaluate_result(query, result) catch_all (e) {
        _ => Evaluation { is_relevant: false, reason: "Error in evaluation" }
    }
}

// extract_learnings with the extractLearningsTool try/catch fallback, plus the
// at-most-one follow-up cap (Mastra's z.array(z.string()).max(1)).
function safe_extract(query: string, result: SearchResult) -> Learning {
    let l = extract_learnings(query, result) catch_all (e) {
        _ => {
            Learning {
                learning: "Error extracting information",
                follow_up_questions: [],
                source: result.url,
            }
        }
    };
    l.follow_up_questions = l.follow_up_questions.slice(0, 1);
    l
}

// Run one search query: search the web, then for each result evaluate relevance and,
// if relevant and the URL is unseen, extract a learning. Returns the per-query findings.
// `seen_urls` is the set of URLs already processed (dedup, ports evaluateResultTool's
// existingUrls check). This function mutates `seen_urls` as it accepts results.
// `phase` labels the returned ResearchData ("initial" or "follow-up").
// Each LLM call degrades gracefully (mirrors evaluateResultTool / extractLearningsTool
// try/catch fallbacks) so one transient failure never aborts the query.
function research_one_query(query: string, seen_urls: string[], phase: string) -> ResearchData {
    let results = exa_search(query);

    // Evaluate every result concurrently, keeping each result paired with its evaluation.
    let evaluated = await baml.future.all(results.map((r) -> {
    spawn {
      EvaluatedResult { result: r, evaluation: safe_evaluate(query, r) }
    }
  }));

    let kept_results: SearchResult[] = [];
    let learnings: Learning[] = [];

    for (let e in evaluated) {
        // Skip if URL already seen (dedup) or judged not relevant.
        if (e.evaluation.is_relevant && !seen_urls.includes(e.result.url)) {
            seen_urls.push(e.result.url);
            kept_results.push(e.result);
            learnings.push(safe_extract(query, e.result));
        }
    }

    ResearchData {
        queries: [query],
        search_results: kept_results,
        learnings: learnings,
        completed_queries: [query],
        phase: phase,
    }
}

// Merge a list of per-query ResearchData into one aggregate.
function merge_research(parts: ResearchData[], phase: string) -> ResearchData {
    let agg = ResearchData {
        queries: [],
        search_results: [],
        learnings: [],
        completed_queries: [],
        phase: phase,
    };
    for (let p in parts) {
        agg.queries = agg.queries.concat(p.queries);
        agg.search_results = agg.search_results.concat(p.search_results);
        agg.learnings = agg.learnings.concat(p.learnings);
        agg.completed_queries = agg.completed_queries.concat(p.completed_queries);
    }
    agg
}

// Collect all follow-up questions from a set of learnings (PHASE 2 input).
function collect_follow_ups(learnings: Learning[]) -> string[] {
    let out: string[] = [];
    for (let l in learnings) {
        for (let q in l.follow_up_questions) {
            if (q != "" && !out.includes(q)) {
                out.push(q);
            }
        }
    }
    out
}

// The full 2-phase research orchestration — ports researchAgent + researchWorkflow.
//   PHASE 1: plan queries -> search/evaluate/extract for each.
//   PHASE 2: collect follow-up questions from Phase-1 learnings -> search/evaluate/extract.
//            STOP — do NOT recurse into Phase-2 follow-ups.
function research_phases(topic: string) -> ResearchData {
    let seen_urls: string[] = [];

    // PHASE 1 — initial research. Fan out the planned queries concurrently.
    let phase1_queries = plan_research_queries(topic);
    let phase1_parts = await baml.future.all(phase1_queries.map((q) -> {
    spawn { research_one_query(q, seen_urls, "initial") }
  }));
    let phase1 = merge_research(phase1_parts, "initial");

    // PHASE 2 — follow-up research from the FIRST round of learnings only.
    let follow_ups = collect_follow_ups(phase1.learnings);
    let phase2_parts = await baml.future.all(follow_ups.map((q) -> {
    spawn { research_one_query(q, seen_urls, "follow-up") }
  }));
    let phase2 = merge_research(phase2_parts, "follow-up");

    // Merge both phases; STOP (no recursion into Phase-2 follow-ups).
    ResearchData {
        queries: phase1.queries.concat(phase2.queries),
        search_results: phase1.search_results.concat(phase2.search_results),
        learnings: phase1.learnings.concat(phase2.learnings),
        completed_queries: phase1.completed_queries.concat(phase2.completed_queries),
        phase: "follow-up",
    }
}

// Public entry point: graceful top-level fallback so a planner failure or any
// uncaught error degrades to empty findings instead of crashing the run
// (mirrors researchWorkflow's research step returning `{ error }`).
function research(topic: string) -> ResearchData {
    research_phases(topic) catch_all (e) {
        _ => {
            ResearchData {
                queries: [],
                search_results: [],
                learnings: [],
                completed_queries: [],
                phase: "initial",
            }
        }
    }
}
