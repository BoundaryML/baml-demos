// LLM clients for bamlcode.
//
// Default brain is Anthropic Claude (set ANTHROPIC_API_KEY).
// To use OpenAI instead, swap `client: Brain` for `client: BrainOpenAI`
// in baml_src/ns_agent/agent.baml (and set OPENAI_API_KEY).

client Brain = anthropic.AnthropicClient.new(
    model = "claude-sonnet-4-6",
    max_tokens = 4096,
);

client BrainOpenAI = openai.OpenAiClient.new(
    model = "gpt-4o",
);
