enum Sentiment {
    Positive,
    Neutral,
    Negative,
    Foo,
}

client AiGatewayImagenImageClient {
    provider: ai-gateway-images,
    options: {
        model: "google/imagen-4.0-fast-generate-001",
        api_key: env.AI_GATEWAY_API_KEY,
        n: 1,
    },
}

function generate_image(thing: string) -> image {
    client: AiGatewayImagenImageClient
    prompt: `
        Create an image from this prompt:

        ${thing}

        ${ctx.output_format}
    `
}

function improving_image(goal: string = "a founder building a programming language") -> image {
    let img = generate_image(goal);
    let judge = evaluate_image(img, goal);

    let attempts = 0;
    while (judge.score < 0.9 && attempts < 1) {
        img = generate_image(goal);
        judge = evaluate_image(img, goal);
        attempts += 1;
    }

    return img;
}

class JudgeResponse {
    score: float,
    reason: string,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            return `Score: ${self.score}, Reason: ${self.reason}`;
        }
    }
}

function evaluate_image(img: image, goal: string) -> JudgeResponse {
    client: "openai/gpt-4o-mini"
    prompt: #"
        Evaluate how well this image matches the goal:
        {{ctx.output_format}}

        {{_.role("user")}}

        Goal: {{goal}}
        Image: {{img}}
    "#
}
