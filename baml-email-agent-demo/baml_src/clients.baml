// LLM clients. The original Vercel app's README maps the roles to OpenAI:
//   research summarization  -> gpt-4o-mini  (cheap, fast)
//   email generation        -> gpt-4o       (stronger writer)
// (The original *code* used Anthropic via the AI Gateway; this demo uses the
// OpenAI provider so it runs with an OPENAI_API_KEY.)
// Both read OPENAI_API_KEY from the environment at call time.

client ResearchModel = openai.OpenAiClient.new(
    model = "gpt-4o-mini",
);

client EmailModel = openai.OpenAiClient.new(
    model = "gpt-4o",
);
