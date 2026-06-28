// Email generation, ported from lib/email/generation.ts (+ schema.ts).
// The prompt builder is pure BAML and unit-tested offline; only
// `generate_emails` actually calls the model.

function default_system_prompt() -> string {
    // Full port of DEFAULT_SYSTEM_PROMPT from lib/email/generation.ts.
    `
        You are generating a 3-email sequence for a prospect.

        Create 3 F-shaped, box-style follow-up emails (~75 words each) with clear CTAs.

        Overall Purpose

        Generate three short, credible, human-like follow-up emails.

        General Formatting Rules

        Each output includes three emails, each with:
        - A subject line
        - A body
        - Length target: ~75 words per email

        Writing style: F-shaped reading pattern
        - Keep paragraphs short (2-3 lines)
        - Left-aligned, skimmable sentences
        - Start directly with the message content
        - Use blank line breaks between paragraphs for consistent rendering
        - Use only active voice - never use passive voice
        - Do not use "would you be interested in?"
        - Be concise and direct. No filler words or phrases
        - No marketing speak or buzzwords (avoid words like "leverage", "synergy", "game-changer", etc.)
        - Professional but not stiff. Conversational but not casual
        - No exclamation points
        - Avoid words ending in -ly

        Company Name Normalization

        When provided with a company name:
        - Remove suffixes: Inc., Ltd., LLC, Limited, Co.
        - Normalize capitalization
        - Use known brand casing when obvious (Stripe, OpenSea)
        - Else default to Title Case
        - Use the cleaned name naturally so it feels manually written, not automated

        Email-Specific Rules

        Email 1:
        - Start with a greeting that includes the prospect's first name, followed by a dash and a reference to their recent activity or interest
        - Connect the outreach to their specific context or need
        - Must include one specific product or feature relevant to the prospect
        - Directly ask for a meeting at end of email

        Email 2:
        - Conversational tone
        - Present one lightweight enhancement idea
        - Briefly explain technical fit
        - End with an offer, not a question, e.g.: "Happy to outline or diagram the architecture."

        Email 3:
        - Slightly assertive tone
        - Highlight one insight or opportunity
        - Suggest a measurable outcome
        - End with a clear, direct CTA question, e.g.: "Should we map this out together?"

        Subject: Under 6 words, shared across all emails

        Tone: Concise, technical, credible. No marketing fluff.
    `
}

// ---------------------------------------------------------------------------
// Section builders (pure)
// ---------------------------------------------------------------------------

function build_contact_section(c: Contact) -> string {
    // Build line-by-line: a leading `\n` inside a backtick string is trimmed
    // (block-string dedent), so optional Title/Notes lines are pushed instead.
    let lines: string[] = ["<contact-information>", "## Contact Information", "", `Name: ${full_name(c)}`];
    if let t: string = c.title {
        let _t = lines.push(`Title: ${t}`);
    }
    let _e = lines.push(`Email: ${c.email}`);
    let _co = lines.push(`Company: ${c.company}`);
    if let n: string = c.notes {
        let _n = lines.push(`Notes: ${n}`);
    }
    let _end = lines.push("</contact-information>");
    lines.join("\n")
}

function build_research_section(company: string, research: CompanyResearch?) -> string {
    if let r: CompanyResearch = research {
        let features = if (r.existing_ai_features.length() > 0) {
            r.existing_ai_features.join(", ")
        } else {
            "None found"
        };
        `
            <company-research>
            ## Company Research

            Company: ${company}
            Summary: ${r.company_summary}
            Existing AI Features (DO NOT suggest these - they already have them): ${features}
            </company-research>
        `
    } else {
        `
            <company-context>
            ## Company Context

            Company: ${company}
            Summary: No research available
            Existing AI Features (DO NOT suggest these - they already have them): Unknown
            </company-context>
        `
    }
}

function build_people_section(name: string, research: PeopleResearch) -> string {
    let activity = if (research.recent_activity.length() > 0) {
        research
            .recent_activity
            .map(
                (a) -> {
                    `- ${a}`
                },
            )
            .join("\n")
    } else {
        "- None found"
    };
    `
        <people-research>
        ## People Research

        Name: ${name}
        Title: ${research.title}
        Summary: ${research.contact_summary}
        Recent Activity:
        ${activity}
        </people-research>
    `
}

function build_format_section(number_of_follow_ups: int) -> string {
    let count = number_of_follow_ups;
    let total = count + 1;
    let email_word = if (total == 1) {
        "email"
    } else {
        "emails"
    };
    let followup_clause = if (count > 0) {
        let fu_word = if (count == 1) {
            "follow-up"
        } else {
            "follow-ups"
        };
        ` + ${count} ${fu_word}`
    } else {
        ""
    };

    `
        <formatting>
        ## Email Output Format

        Generate ${total} ${email_word} (1 initial${followup_clause}).

        Format each email body as plain HTML:
        - Use <p> tags to wrap each paragraph for proper spacing
        - After each </p> tag, use <br> tags for line breaks between paragraphs
        - Do NOT use any inline styles, CSS classes, or styling attributes
        - Keep paragraphs short (2-3 lines) for F-shaped reading pattern
        - Example: <p>First paragraph here.</p><br><p>Second paragraph here.</p><br><p>Third paragraph here.</p>

        Write ONLY the email body content. Do not include:
        - Greetings like "Hi [Name]" (these will be added automatically)
        - Sign-offs or signatures (these will be added automatically)
        - Any placeholder text or variables

        Return exactly ${total} ${email_word} in \`bodies\`.
        </formatting>
    `
}

// ---------------------------------------------------------------------------
// Main prompt builder (pure) — same section order as the TS original.
// ---------------------------------------------------------------------------

function build_email_prompt(
    contact: Contact,
    campaign: Campaign,
    company_research: CompanyResearch?,
    people_research: PeopleResearch?,
) -> string {
    let sections: string[] = [];

    let _a = sections.push(build_contact_section(contact));
    let _b = sections
        .push(
            `
                <instructions>
                ## Instructions

                ${campaign.system_prompt}
                </instructions>
            `,
        );

    if (campaign.research_enabled) {
        let _c = sections.push(build_research_section(contact.company, company_research));
    }

    if (campaign.people_research_enabled) {
        if let pr: PeopleResearch = people_research {
            let _d = sections.push(build_people_section(full_name(contact), pr));
        }
    }

    let _e = sections.push(build_format_section(campaign.number_of_follow_ups));

    sections.join("\n\n")
}

// ---------------------------------------------------------------------------
// The one LLM call
// ---------------------------------------------------------------------------

function generate_emails(
    contact: Contact,
    campaign: Campaign,
    company_research: CompanyResearch?,
    people_research: PeopleResearch?,
) -> EmailSequence {
    client: EmailModel
    prompt: `
        ${build_email_prompt(contact, campaign, company_research, people_research)}

        ${ctx.output_format}
    `
}

// ---------------------------------------------------------------------------
// Offline tests — exercise the pure builders on literal data, no model call.
// ---------------------------------------------------------------------------

testset "email_prompt_tests" {
    test "format section pluralizes and counts correctly" {
        assert.contains(build_format_section(0), "Generate 1 email (1 initial).");
        assert.contains(build_format_section(1), "Generate 2 emails (1 initial + 1 follow-up).");
        assert.contains(build_format_section(2), "Generate 3 emails (1 initial + 2 follow-ups).")
    }

    test "contact section puts each field on its own line" {
        let c = Contact {
            first_name: "Sarah",
            last_name: "Chen",
            email: "sarah@acme.io",
            title: "VP Eng",
            company: "Acme",
            notes: "Met at booth",
        };
        let section = build_contact_section(c);
        assert.contains(section, "Name: Sarah Chen\nTitle: VP Eng\nEmail: sarah@acme.io");
        assert.contains(section, "Company: Acme\nNotes: Met at booth");

        // Optional lines vanish cleanly when absent (no dangling label).
        let bare = build_contact_section(
            Contact {
                first_name: "Cher",
                last_name: null,
                email: "c@x.io",
                company: "Acme",
                title: null,
                notes: null,
            },
        );
        assert.contains(bare, "Name: Cher\nEmail: c@x.io\nCompany: Acme\n");
        assert.is_true(!bare.includes("Title:"));
        assert.is_true(!bare.includes("Notes:"))
    }

    test "research section switches on presence and lists features" {
        let with_research = build_research_section(
            "Acme",
            CompanyResearch {
                company_summary: "Makes widgets.",
                existing_ai_features: ["autocomplete", "search"],
            },
        );
        assert.contains(with_research, "Summary: Makes widgets.");
        assert.contains(with_research, "autocomplete, search");

        let without = build_research_section("Acme", null);
        assert.contains(without, "No research available")
    }

    test "full prompt includes contact, instructions, and formatting; omits people when disabled" {
        let contact = Contact {
            first_name: "Sarah",
            last_name: "Chen",
            email: "sarah@acme.io",
            title: "VP Eng",
            company: "Acme",
            notes: "Met at booth",
        };
        let campaign = Campaign {
            name: "ReInvent",
            system_prompt: "Be warm and technical.",
            research_enabled: true,
            people_research_enabled: false,
            number_of_follow_ups: 2,
        };
        let prompt = build_email_prompt(contact, campaign, null, null);
        assert.contains(prompt, "Name: Sarah Chen");
        assert.contains(prompt, "Title: VP Eng");
        assert.contains(prompt, "Be warm and technical.");
        assert.contains(prompt, "## Company Context");
        assert.contains(prompt, "Generate 3 emails");
        assert.is_true(!prompt.includes("## People Research"))
    }
}
