client DefaultLogo = google.GeminiClient.new(
    model = "gemini-3.1-flash-image",
    api_key = env.GEMINI_API_KEY,
    response_modalities = ["IMAGE"],
);

client DefaultCopy = openai.ResponsesClient.new(
    model = "gpt-5.2",
    api_key = env.OPENAI_API_KEY,
    request_timeout_ms = 120000,
);

function DefaultModel(function_name: root.AssetFunction) -> root.ModelChoice {
    if (function_name == "GenerateLogo") {
        root.ModelChoice { provider: "google", model: "gemini-3.1-flash-image" }
    } else {
        root.ModelChoice { provider: "openai", model: "gpt-5.2" }
    }
}

function MakeClient(function_name: root.AssetFunction, choice: root.ModelChoice) -> ai.Client {
    if (choice.provider == "google") {
        google.GeminiClient.new(
            model = choice.model,
            api_key = env.GEMINI_API_KEY,
            response_modalities = if (function_name == "GenerateLogo") {
                ["IMAGE"]
            } else {
                ["TEXT"]
            },
        )
    } else if (choice.provider == "openai") {
        if (function_name == "GenerateLogo") {
            openai.ImageClient.new(
                model = choice.model,
                api_key = env.OPENAI_API_KEY,
                size = "1024x1024",
                quality = "low",
            )
        } else {
            openai.ResponsesClient.new(
                model = choice.model,
                api_key = env.OPENAI_API_KEY,
                request_timeout_ms = 120000,
            )
        }
    } else {
        throw baml.errors.InvalidArgument { message: "Choose the openai or google provider" }
    }
}
