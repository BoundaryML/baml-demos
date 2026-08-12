// Learn more about clients at https://docs.boundaryml.com/docs/snippets/clients/overview

function add(a: int, b: int) -> int {
    a + b
}

client CustomGPT5 = openai.OpenAiClient.new(
    model = "gpt-5",
    api_key_env = "TEMP_KEY",
);

client CustomGPT5Mini = ai.clients.Retry.new(
    inner = openai.OpenAiClient.new(
        model = "gpt-5-mini",
    ),
    max_attempts = 2,
);

client CustomGPT5Chat = openai.OpenAiClient.new(
    model = "gpt-5",
);

client CustomOpus4 = anthropic.AnthropicClient.new(
    model = "claude-opus-4-1-20250805",
);

client CustomSonnet4 = anthropic.AnthropicClient.new(
    model = "claude-sonnet-4-20250514",
);

client CustomHaiku = anthropic.AnthropicClient.new(
    model = "claude-haiku-4-5",
);

// Example Google AI client (uncomment to use)
// client CustomGemini = google.GoogleClient.new(
//     model = "gemini-2.5-pro",
// );

// This will alternate between the two clients.
client CustomFast = ai.clients.RoundRobin.new([CustomGPT5Mini, CustomHaiku]);

// This will try the clients in order until one succeeds.
client OpenaiFallback = ai.clients.Fallback {
    members: [CustomGPT5Mini, CustomGPT5],
};

function will_double(x: int) -> int {
    x * 2
}

function double() -> void {
    let doubled = [1, 2, 3].map(will_double);
    log.info({ "doubled": doubled });
}
