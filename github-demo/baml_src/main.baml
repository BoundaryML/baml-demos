client<llm> DemoModel {
    provider: openai,
    options: {
        model: "gpt-5-mini",
    },
}

enum Confidence {
    Low,
    Medium,
    High,
}

class ResearchQuestion {
    question: string @description("A concrete question the report should answer."),
    why_it_matters: string @description("Why the reader should care about this question."),
}

class TopicPlan {
    title: string @description("A short, audience-friendly working title."),
    audience: string @description("The most likely audience for this brief."),
    questions: ResearchQuestion[] @description("The main questions to investigate."),
    success_criteria: string[] @description("Checks the final answer should satisfy."),
}

class ResearchFinding {
    claim: string @description("A factual claim or useful framing."),
    evidence: string @description("Concise support for the claim. Do not invent citations."),
    confidence: Confidence,
}

class ResearchPack {
    topic: string,
    findings: ResearchFinding[],
    gaps: string[] @description("Important unknowns or caveats the final article should mention."),
}

class CoverImageTask {
    asset_kind: "cover",
    prompt: string @description("Prompt a renderer could use to create the cover image."),
    alt_text: string @description("Accessible alt text for the generated cover."),
    palette: string[] @description("Three to five concrete visual color/style notes."),
}

class ArticleDraft {
    headline: string,
    dek: string @description("One sentence summary shown under the headline."),
    sections: string[] @description("Short article sections ready for UI rendering."),
    takeaways: string[] @description("Punchy bullets for a sidebar."),
}

class ArticlePackage {
    topic: string,
    title: string,
    cover: CoverImageTask,
    draft: ArticleDraft,
    confidence_note: string,
}

class DemoError {
    message: string,
    recoverable: bool,
}

type PackageResult = ArticlePackage | DemoError;

function GenerateTopicPlan(topic: string) -> TopicPlan {
    client: DemoModel
    prompt: `
        Turn this topic into a compact editorial plan.

        Topic: ${topic}

        Prefer specific, inspectable fields over prose blobs.
        ${ctx.output_format}
    `
}

function ResearchTopic(plan: TopicPlan) -> ResearchPack {
    client: DemoModel
    prompt: `Research the topic plan below as if preparing a concise technical article.

Title: ${plan.title}
Audience: ${plan.audience}
Questions:
${plan.questions.map((q) -> { "- " + q.question + " (" + q.why_it_matters + ")" }).join("\n")}

Return structured findings, caveats, and confidence. Do not fabricate citations.
${ctx.output_format}`
}

function CreateCoverImageTask(plan: TopicPlan) -> CoverImageTask {
    client: DemoModel
    prompt: `
        Create a cover image generation task for this article.

        Title: ${plan.title}
        Audience: ${plan.audience}

        The output is not prose. It is a typed image task another system can render.
        ${ctx.output_format}
    `
}

function DraftArticle(plan: TopicPlan, research: ResearchPack) -> ArticleDraft {
    client: DemoModel
    prompt: `Write a concise article draft from typed research.

Title: ${plan.title}
Audience: ${plan.audience}
Success criteria:
${plan.success_criteria.map((c) -> { "- " + c }).join("\n")}

Findings:
${research.findings.map((f) -> { "- " + f.claim + " Evidence: " + f.evidence + ". Confidence: " + f.confidence.to_string() }).join("\n")}

Known gaps:
${research.gaps.map((g) -> { "- " + g }).join("\n")}

Keep it useful for a product/engineering demo.
${ctx.output_format}`
}

function require_showcase_topic(topic: string) -> string throws baml.errors.InvalidArgument {
    let normalized = topic.trim();
    if (normalized.length() < 8) {
        throw baml.errors.InvalidArgument { message: "topic must be at least 8 characters after trimming" }
    } else if (normalized.to_lower_case().includes("secret")) {
        throw baml.errors.InvalidArgument { message: "topic should not include private or secret material" }
    } else {
        normalized
    }
}

function confidence_note(pack: ResearchPack) -> string {
    let high_count = pack
        .findings
        .filter(
            (f) -> {
                f.confidence == Confidence.High
            },
        )
        .length();
    let total = pack.findings.length();
    if (total == 0) {
        "No findings were returned; treat this as a draft scaffold."
    } else {
        high_count.to_string()
            + "/"
            + total.to_string()
            + " findings were marked high confidence; review gaps before publishing."
    }
}

function summarize_gaps(pack: ResearchPack) -> string {
    if (pack.gaps.length() == 0) {
        "No explicit research gaps."
    } else {
        pack.gaps.join("; ")
    }
}

function render_markdown(pkg: ArticlePackage) -> string {
    let takeaways = pkg
        .draft
        .takeaways
        .map(
            (t) -> {
                "- " + t
            },
        )
        .join("\n");
    let body = pkg.draft.sections.join("\n\n");
    "# "
        + pkg.draft.headline
        + "\n\n"
        + pkg.draft.dek
        + "\n\nCover prompt: "
        + pkg.cover.prompt
        + "\n\n## Takeaways\n"
        + takeaways
        + "\n\n## Body\n"
        + body
}

function demo_describe_targets() -> string[] {
    [
        "baml describe ArticlePackage --budget 160",
        "baml describe GenerateTopicPlan --budget 120",
        "baml describe PackageResult --budget 120",
        "baml describe require_showcase_topic --budget 120",
    ]
}

function BuildTopicPackage(topic: string) -> ArticlePackage {
    //# Validate contract
    let clean_topic = require_showcase_topic(topic);
    //# Plan with typed LLM function
    let plan = GenerateTopicPlan(clean_topic);
    //# Fan out cover task and research in parallel
    let cover_future = spawn { CreateCoverImageTask(plan) };
    let research_future = spawn { ResearchTopic(plan) };
    //# Await typed branch results
    let cover = await cover_future;
    let research = await research_future;
    //# Draft from structured research
    let draft = DraftArticle(plan, research);
    //# Assemble typed package
    ArticlePackage {
        topic: clean_topic,
        title: plan.title,
        cover: cover,
        draft: draft,
        confidence_note: confidence_note(research) + " Gaps: " + summarize_gaps(research),
    }
}

function demo_pipeline() -> ArticlePackage {
    BuildTopicPackage("how typed LLM workflows change product engineering")
}

function demo_pipeline_safe() -> PackageResult {
    BuildTopicPackageSafe("tiny")
}

function demo_pipeline_markdown() -> string {
    render_markdown(demo_pipeline())
}

function BuildTopicPackageSafe(topic: string) -> PackageResult {
    BuildTopicPackage(topic) catch (e) {
        baml.errors.InvalidArgument => DemoError { message: e.message, recoverable: true },
    }
}

function sample_research_pack() -> ResearchPack {
    ResearchPack {
        topic: "typed LLM workflows",
        findings: [
            ResearchFinding {
                claim: "Typed schemas make model boundaries explicit.",
                evidence: "The caller receives a ResearchPack instead of parsing free text.",
                confidence: Confidence.High,
            },
            ResearchFinding {
                claim: "Pure post-processing can be tested without a model call.",
                evidence: "confidence_note and markdown operate on literal BAML values.",
                confidence: Confidence.High,
            },
            ResearchFinding {
                claim: "Parallel branches keep independent work separate.",
                evidence: "The cover task and research task are spawned from the same plan.",
                confidence: Confidence.Medium,
            },
        ],
        gaps: ["Live citations would need an external search/retrieval tool."],
    }
}

test "validator throws but callers can contain it at the boundary" {
    let result = BuildTopicPackageSafe("tiny");
    if let err: DemoError = result {
        assert.equal(err.recoverable, true);
        assert.contains(err.message, "topic must be")
    } else {
        assert.is_true(false)
    }
}

test "pure summary code is testable without an LLM" {
    let pack = sample_research_pack();
    assert
        .equal(
            confidence_note(pack),
            "2/3 findings were marked high confidence; review gaps before publishing.",
        );
    assert
        .equal(summarize_gaps(pack), "Live citations would need an external search/retrieval tool.")
}

test "describe targets are executable CLI hints, not grep strings" {
    let targets = demo_describe_targets();
    assert.equal(targets.length(), 4);
    assert.contains(targets.join("\n"), "baml describe ArticlePackage")
}
