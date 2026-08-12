// LLM clients — port of the model choices from the Mastra agents.
// webSummarizationAgent uses gpt-4.1-mini (cheap, summarization) -> Fast
// evaluation/learning/report agents use gpt-4.1 (smarter) -> Smart
// researchAgent (the tool-calling planner) used gpt-4o -> Planner

client Fast = openai.OpenAiClient.new(
    model = "gpt-4.1-mini",
);

client Smart = openai.OpenAiClient.new(
    model = "gpt-4.1",
);

// Ports researchAgent's planner model (Mastra used openai/gpt-4o for the
// tool-calling planner; only its query-breakdown survives as plan_research_queries).
client Planner = openai.OpenAiClient.new(
    model = "gpt-4o",
);
