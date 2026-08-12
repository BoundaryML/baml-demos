client AiGatewayImagenImageClient = openai.OpenAiClient.new(
    model = "google/imagen-4.0-fast-generate-001",
    api_key_env = "AI_GATEWAY_API_KEY",
    base_url = "https://ai-gateway.vercel.sh/v1",
);

function generate_image(thing: string) -> image {
    client: AiGatewayImagenImageClient
    prompt: `
        Create an image from this prompt:

        ${thing}

        ${ctx.output_format}
    `
}
