// Research, ported from lib/research/company.ts and lib/research/people.ts.
//
// Original: two parallel Exa `searchAndContents` calls -> filter sources ->
// one Haiku call to summarize/verify. Here the Exa HTTP call AND the LLM
// summarization both live in BAML: `spawn { ... }` + `baml.future.all`
// replace the TS `Promise.all`, and the model output is a typed return value.

class ExaSource {
    url: string,
    summary: string,
}

// Just the fields we read from the Exa /search response; extras are ignored.
class ExaResult {
    url: string?,
    summary: string?,
}

class ExaResponse {
    results: ExaResult[],
}

// One Exa semantic search with content summaries. Resilient: a missing key or
// any HTTP/parse failure collapses to an empty source list so research degrades
// gracefully, exactly like the original try/catch (which also swallowed the
// missing-key throw from getExaClient()).
function exa_search(query: string, num_results: int, category: string?) -> ExaSource[] {
    // Non-panicking key read: absence yields no sources rather than crashing.
    let key = baml.env.get("EXA_API_KEY") ?? "";
    if (key == "") {
        []
    } else {
        let category_field = if let c: string = category {
            `"category": ${baml.json.to_string(c)}, `
        } else {
            ""
        };
        let body = `{"query": ${baml.json.to_string(query)}, "numResults": ${num_results}, "type": "auto", ${category_field}"contents": {"summary": true}}`;

        let request = baml.http.Request {
            method: "POST",
            url: "https://api.exa.ai/search",
            headers: { "x-api-key": key, "content-type": "application/json" },
            body: body,
        };

        // Any HTTP/parse failure collapses to no sources.
        let parsed = baml.json.from_string<ExaResponse>(baml.http.send(request).text()) catch_all (e) {
            _ => ExaResponse { results: [] }
        };
        parsed
            .results
            .filter(
                (r) -> {
                    r.url != null && r.summary != null
                },
            )
            .map(
                (r) -> {
                    ExaSource { url: r.url ?? "", summary: r.summary ?? "" }
                },
            )
    }
}

// Render sources the way the original prompt did: "URL: ...\nSummary: ..." blocks.
function render_sources(sources: ExaSource[]) -> string {
    sources
        .map(
            (s) -> {
                `URL: ${s.url}\nSummary: ${s.summary}`
            },
        )
        .join("\n\n")
}

// ---------------------------------------------------------------------------
// Company research
// ---------------------------------------------------------------------------

function research_company(company_name: string) -> CompanyResearch {
    // Two searches run concurrently (green threads), then await + merge both.
    let search1 = spawn { exa_search(`${company_name} AI features products`, 3, "company") };
    let search2 = spawn { exa_search(`${company_name} engineering blog AI`, 2, "news") };
    let sources = (
        await search1
    )
    .concat(
        await search2,
    );

    if (sources.length() == 0) {
        // Same fallback the TS version returns when Exa finds nothing.
        CompanyResearch {
            company_summary: `${company_name} is a company.`,
            existing_ai_features: [],
        }
    } else {
        summarize_company(company_name, sources)
    }
}

function summarize_company(company_name: string, sources: ExaSource[]) -> CompanyResearch {
    client: ResearchModel
    prompt: `
        Based on the following research results about ${company_name}, extract:
        1. Any AI features or products they already offer
        2. A brief summary of what the company does

        Research results:
        ${render_sources(sources)}

        If no AI features are found, return an empty array for existing_ai_features.

        ${ctx.output_format}
    `
}

// ---------------------------------------------------------------------------
// People research
// ---------------------------------------------------------------------------

// The model verifies the match before we trust the profile (the original's
// isConfidentMatch / matchedCompany gate).
class PeopleVerification {
    is_confident_match: bool @description("True ONLY if results clearly match the same person (name AND company)"),
    matched_company: string? @description("Company name found in results, or null"),
    title: string,
    contact_summary: string,
    recent_activity: string[],
}

function research_person(name: string, email: string, company: string) -> PeopleResearch? {
    let search1 = spawn { exa_search(`"${name}" "${company}"`, 3, "people") };
    let search2 = spawn { exa_search(`"${name}" (speaker OR conference OR blog OR article)`, 2, null) };
    let sources = (
        await search1
    )
    .concat(
        await search2,
    );

    if (sources.length() == 0) {
        null
    } else {
        let v = verify_person(name, email, company, sources);
        // Drop low-confidence or unverified matches, like the original.
        if (v.is_confident_match && v.matched_company != null) {
            PeopleResearch {
                title: v.title,
                contact_summary: v.contact_summary,
                recent_activity: v.recent_activity,
            }
        } else {
            null
        }
    }
}

// "<name> who works at <company>[ (email: <email>)]" — the email clause is
// omitted when empty, matching the original's `contactEmail ? … : ''` guard.
function person_descriptor(name: string, company: string, email: string) -> string {
    let email_part = if (email == "") {
        ""
    } else {
        ` (email: ${email})`
    };
    `${name} who works at ${company}${email_part}`
}

function verify_person(
    name: string,
    email: string,
    company: string,
    sources: ExaSource[],
) -> PeopleVerification {
    client: ResearchModel
    prompt: `
        You are verifying whether search results match a specific person: ${person_descriptor(name, company, email)}.

        Set is_confident_match=true ONLY if you find clear evidence this is the same person (company and name must match). If results seem to be about a different person with a similar name, set is_confident_match=false.

        Extract the following from the search results:
        - Their current title/role
        - A professional summary of who they are
        - Any recent public activity (talks, blog posts, articles, etc.)

        Search results:
        ${render_sources(sources)}

        ${ctx.output_format}
    `
}

test "person_descriptor omits the email clause when empty" {
    assert
        .equal(
            person_descriptor("Ada Lovelace", "Analytical", "ada@x.io"),
            "Ada Lovelace who works at Analytical (email: ada@x.io)",
        );
    assert
        .equal(
            person_descriptor("Ada Lovelace", "Analytical", ""),
            "Ada Lovelace who works at Analytical",
        )
}

test "render_sources formats URL/summary blocks" {
    let s = render_sources(
        [
            ExaSource { url: "https://a.com", summary: "First" },
            ExaSource { url: "https://b.com", summary: "Second" },
        ],
    );
    assert.equal(s, "URL: https://a.com\nSummary: First\n\nURL: https://b.com\nSummary: Second")
}
