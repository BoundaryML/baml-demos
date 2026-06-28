// Shared types — ports of the zod schemas from the Mastra tools/workflows.

// A summarized web search result (webSearchTool output element).
class SearchResult {
    title: string,
    url: string,
    content: string,
}

// evaluateResultTool structured output.
class Evaluation {
    is_relevant: bool @description("true if the result genuinely helps answer the query"),
    reason: string @description("brief, specific explanation of the decision"),
}

// extractLearningsTool structured output (max 1 follow-up question).
class Learning {
    learning: string @description("the single most important insight from the content"),
    follow_up_questions: string[] @description("up to 1 focused follow-up question for deeper research"),
    source: string @description("the URL the learning came from"),
}

// The aggregate research findings — ports researchWorkflow's researchData object.
class ResearchData {
    queries: string[],
    search_results: SearchResult[],
    learnings: Learning[],
    completed_queries: string[],
    phase: string,
}
