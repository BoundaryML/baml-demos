// Domain types. These mirror the Drizzle schema + zod shapes from the
// original Next.js app (db/schema.ts, lib/email/schema.ts), minus the
// persistence/CRM plumbing — the demo keeps the *AI* surface in BAML.

class Campaign {
    name: string,
    // Free-form instructions the operator writes for the AI (the "system prompt").
    system_prompt: string,
    research_enabled: bool,
    people_research_enabled: bool,
    // 0..2 follow-ups => a 1..3 email sequence.
    number_of_follow_ups: int,
}

class Contact {
    first_name: string,
    last_name: string?,
    email: string,
    title: string?,
    company: string,
    notes: string?,
}

class CompanyResearch {
    company_summary: string @description("Brief summary of what the company does"),
    existing_ai_features: string[] @description("AI features/products the company already offers"),
}

class PeopleResearch {
    title: string @description("The person's role/title"),
    contact_summary: string @description("Summary of who they are professionally"),
    recent_activity: string[] @description("Recent public activity: talks, blog posts, articles, etc."),
}

// The generated email sequence. The original used dynamic body1/body2/body3
// fields; a typed list is the idiomatic BAML shape and carries the same data.
class EmailSequence {
    subject: string @description("Email subject line — concise, under 6 words, shared across all emails"),
    bodies: string[] @description("One body per email, plain HTML using <p> tags for spacing, no inline styles"),
}

// Everything the workflow produces for one contact.
class ProcessedContact {
    contact: Contact,
    company_research: CompanyResearch?,
    people_research: PeopleResearch?,
    emails: EmailSequence,
}

// `"First Last"` with the optional last name trimmed off when absent.
function full_name(c: Contact) -> string {
    let last = c.last_name ?? "";
    if (last == "") {
        c.first_name
    } else {
        `${c.first_name} ${last}`
    }
}

test "full_name handles a missing last name" {
    assert
        .equal(
            full_name(Contact { first_name: "Sarah", last_name: "Chen", email: "s@x.io", company: "Acme" }),
            "Sarah Chen",
        );
    assert
        .equal(
            full_name(Contact { first_name: "Cher", last_name: null, email: "c@x.io", company: "Acme" }),
            "Cher",
        )
}
