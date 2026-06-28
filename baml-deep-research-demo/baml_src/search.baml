// Web search — ports webSearchTool + webSummarizationAgent.
// Exa POST, then summarize each result's content concurrently.

class ExaResult {
    title: string?,
    url: string,
    text: string?,
}

class ExaResponse {
    results: ExaResult[],
}

// Ports webSummarizationAgent: turn long web content into a concise summary
// focused on the research query. Plain string return -> no ${ctx.output_format}.
function summarize_web(query: string, title: string, url: string, content: string) -> string {
    client: Fast
    prompt: `
        You are a web content summarization specialist. Create a concise, informative summary
        that captures the essential information while being significantly shorter than the original
        (reduce by 80-95%). Focus on information relevant to the research query.

        Structure the summary with:
        - Main Topic: what the content is about
        - Key Insights: 3-5 most important findings, facts, and conclusions
        - Supporting Details: specific examples, evidence, statistics
        - Context: source/date/author if available

        Research query: "${query}"

        Title: ${title}
        URL: ${url}
        Content: ${content}

        Concise summary:
    `
}

// POST to Exa and parse the result list. Returns [] on a 4xx/5xx status or a
// non-conforming body — callers wrap this in catch_all so a bad/expired key, an
// Exa outage, or a rate-limit response degrades to "no results" instead of
// aborting the whole research run (mirrors webSearchTool's `{ results: [] }`).
function fetch_exa_results(query: string, num_results: int) -> ExaResult[] {
    let body = baml.json.to_string({ "query": query, "numResults": num_results, "contents": { "text": true } });
    let req = baml.http.Request {
        method: "POST",
        url: "https://api.exa.ai/search",
        headers: { "x-api-key": env.EXA_API_KEY, "content-type": "application/json" },
        body: body,
    };
    let resp = baml.http.send(req);
    if (resp.status_code >= 400) {
        return [];
    }
    baml.json.from_string<ExaResponse>(resp.text()).results
}

// Ports webSearchTool.execute: Exa search (numResults=2) + per-result summarization.
// Any Exa transport/parse error yields [] (graceful degradation, per webSearchTool).
function exa_search(query: string, num_results: int = 2) -> SearchResult[] {
    let results: ExaResult[] = fetch_exa_results(query, num_results) catch_all (e) {
        _ => []
    };
    let futures = results
        .map(
            (r) -> {
                spawn {
                let txt = r.text ?? "";
                // Mirror Mastra: skip summarization for short content (< 100 chars),
                // cap summarizer input at 8000 chars, and on a summarize failure fall
                // back to the first 500 chars of raw text (webSearchTool's catch path).
                let content = if (txt.length() >= 100) {
                    summarize_web(query, r.title ?? "", r.url, txt.substring(0, 8000)) catch_all (e) {
                        _ => txt.substring(0, 500)
                    }
                } else if (txt == "") {
                    "No content available"
                } else {
                    txt
                };
                SearchResult { title: r.title ?? "", url: r.url, content: content }
            }
            },
        );
    await baml.future.all(futures)
}
