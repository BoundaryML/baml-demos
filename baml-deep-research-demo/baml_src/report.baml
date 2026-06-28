// Report generation — ports reportAgent + generateReportWorkflow's report step.

// Render the research findings into a compact text block the report model can read.
// (Ports the `JSON.stringify(researchData)` the Mastra report step passes in.)
function research_to_text(data: ResearchData) -> string {
    let queries = data.queries.join("\n- ");
    let learnings = data
        .learnings
        .map(
            (l) -> {
                `- ${l.learning} (source: ${l.source})`
            },
        )
        .join("\n");
    let sources = data
        .search_results
        .map(
            (r) -> {
                `- ${r.title} — ${r.url}\n  ${r.content}`
            },
        )
        .join("\n");
    let follow_ups = collect_follow_ups(data.learnings).join("\n- ");
    `
        Phase: ${data.phase}

        Queries used:
        - ${queries}

        Key learnings:
        ${learnings}

        Follow-up questions identified:
        - ${follow_ups}

        Sources (title — url, summarized content):
        ${sources}
    `
}

// Ports reportAgent: comprehensive, expert-tone markdown report from research data.
// `today` is the current date (passed from the caller, like Mastra's
// `Today is ${new Date().toISOString()}`) so the model can anchor post-cutoff news.
function generate_report(data: ResearchData, today: string) -> string {
    client: Smart
    prompt: `
        You are an expert researcher. Today is ${today}. Follow these instructions when responding:
        - You may be asked to research subjects after your knowledge cutoff; assume the user is right when presented with news.
        - The user is a highly experienced analyst — do not simplify; be as detailed as possible and correct.
        - Be highly organized.
        - Suggest solutions the user might not have thought about.
        - Be proactive and anticipate the user's needs.
        - Treat the user as an expert in all subject matter.
        - Mistakes erode trust, so be accurate and thorough.
        - Provide detailed explanations; the user is comfortable with lots of detail.
        - Value good arguments over authorities; the source is irrelevant.
        - Consider new technologies and contrarian ideas, not just conventional wisdom.
        - You may use high levels of speculation or prediction, just flag it.
        - Use Markdown formatting.

        Generate a comprehensive report based on the research data below, which includes the search
        queries used, relevant search results, key learnings extracted, and follow-up questions.
        Structure the report with clear sections and headings, and synthesize the information into a
        cohesive narrative rather than simply listing facts.

        Research data:
        ${research_to_text(data)}

        Report (Markdown):
    `
}
