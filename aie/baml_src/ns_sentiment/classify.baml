enum Sentiment {
    Positive,
    Neutral,
    Negative,
}

class Group {
    sentiment: Sentiment,
    reason: string @description("5 words"),
}

function classify(text: string) -> Group[] {
    client: "openai/gpt-4o-mini"
    prompt: #"
        Classify the sentiment of this text as Positive, Neutral, or Negative.
        {{ctx.output_format}}

        {{_.role("user")}}

        Text: {{text}}
    "#
}

function judge(text: string, got: Sentiment, expected: Sentiment | null = null) -> bool {
    client: "openai/gpt-4o-mini"
    prompt: `
        Judge if the sentiment classification is correct.
        ${ctx.output_format}
        ${if expected != null}
        Expected: ${expected}
        ${endif}

        ${role("user")}

        Text: ${text}
        Classification: ${got}
    `
}

test "parsing1" {
    let raw = `the answer is { sentiment: the answer is neutral or positive,\nreason: "the answer is neutral" }`;

    let result = classify$parse(raw);
    log.info(result);
    assert.equal(result, [Group { sentiment: Sentiment.Neutral, reason: "the answer is neutral" }]);
}

test "parsing2" {
    let raw = `the answer is neutral`;

    let result = classify$parse(raw);
    log.info(result);
    assert.equal(result, [Sentiment.Neutral]);
}

test "bad2" {
    let result = classify("I hate this product!");
    assert.equal(result, Sentiment.Negative);
}

test "input/manual" {
    let input = baml.io.input("answer?");
    let result = classify(input);
    assert.equal(result, Sentiment.Negative);
}

testset "all-bad" with testing.PassRate(0.5) {
    let options = ["I hate this product!", "This is the worst experience I've ever had."];
    for (let i in options) {
        test `bad:${i}` with testing.Retry(3) {
            let result = classify(i);
            assert.is_true(judge(i, result[0].sentiment, expected = Sentiment.Negative));
        }
    }
}
