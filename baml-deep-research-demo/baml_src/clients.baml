// LLM clients — port of the model choices from the Mastra agents.
// webSummarizationAgent uses gpt-4.1-mini (cheap, summarization) -> Fast
// evaluation/learning/report agents use gpt-4.1 (smarter) -> Smart
// researchAgent (the tool-calling planner) used gpt-4o -> Planner

client<llm> Fast {
    provider: openai,
    options: {
        model: "gpt-4.1-mini",
        api_key: env.OPENAI_API_KEY,
    },
}

client<llm> Smart {
    provider: openai,
    options: {
        model: "gpt-4.1",
        api_key: env.OPENAI_API_KEY,
    },
}

// Ports researchAgent's planner model (Mastra used openai/gpt-4o for the
// tool-calling planner; only its query-breakdown survives as plan_research_queries).
client<llm> Planner {
    provider: openai,
    options: {
        model: "gpt-4o",
        api_key: env.OPENAI_API_KEY,
    },
}
