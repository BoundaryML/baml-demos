// The BAML tool functions run on OpenAI (same convention as the other demos
// in this repo), while the ADK agent that *calls* them runs on Gemini.
// Two providers, cleanly separated: Gemini orchestrates, BAML executes.

client<llm> ExpenseModel {
    provider: openai,
    options: {
        model: "gpt-4o-mini",
        api_key: env.OPENAI_API_KEY,
    },
}
