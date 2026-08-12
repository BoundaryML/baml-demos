// LLM clients for bamlcode.
//
// Credentials are resolved when the selected client makes a request.

client Brain = anthropic.AnthropicClient.new(
    model = "claude-sonnet-4-6",
    max_tokens = 4096,
);

client BrainOpenAI = openai.OpenAiClient.new(
    model = "gpt-4o",
);

function resolve_client(provider: string) -> ai.Client {
    match (provider.trim().to_lower_case()) {
        "anthropic" => Brain,
        "openai" => BrainOpenAI,
        _ => {
            throw baml.errors.InvalidArgument {
                message: `unknown provider "${provider}"; expected anthropic or openai`,
            }
        },
    }
}

function require_provider_credentials(provider: string) -> null {
    let key_name = match (provider.trim().to_lower_case()) {
        "anthropic" => "ANTHROPIC_API_KEY",
        "openai" => "OPENAI_API_KEY",
        _ => {
            throw baml.errors.InvalidArgument {
                message: `unknown provider "${provider}"; expected anthropic or openai`,
            }
        },
    };
    if (baml.env.get(key_name) == null) {
        throw baml.errors.InvalidArgument {
            message: `${key_name} is not set; export it or choose another provider`,
        }
    };
    null
}
