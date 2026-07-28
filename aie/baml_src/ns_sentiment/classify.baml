enum Sentiment {
    Positive,
    Neutral,
    Negative,
}

class Group {
    sentiment: Sentiment,
    result: string,
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

test "parsing" {
    let raw = `{ sentiment: the answer is neutral,\nresult: "the answer is neutral" }`;

    let result = classify$parse(raw);
    log.info(result);
    assert.equal(result, [Group { sentiment: Sentiment.Neutral, result: "the answer is neutral" }]);
}

test "parsing2" {
    let raw = `the answer is neutral`;

    let result = classify$parse(raw);
    log.info(result);
    assert.equal(result, [Sentiment.Neutral]);
}

test "bad" {
    let result = classify("I hate this product!");
    assert.equal(result, Sentiment.Negative);
}

testset "all-bad" {
    let options = ["I hate this product!", "This is the worst experience I've ever had."];
    for (let i in options) {
        test `bad:${i}` {
            let result = classify(i);
            assert.equal(result, Sentiment.Negative);
        }
    }
}

