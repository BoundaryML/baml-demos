// Orchestration, ported from workflows/process-contact.ts.
//
// The TS version was a durable Vercel Workflow with one "use step" per stage
// (load -> research company -> research person -> save -> generate -> save ->
// CRM). The AI-relevant core is: research (concurrently), then generate. The
// Python bridge drives persistence/CRM; BAML owns the agent logic.

function process_contact(contact: Contact, campaign: Campaign) -> ProcessedContact {
    // Company + people research run concurrently as green threads; each branch
    // is gated on the campaign toggle and yields null when disabled.
    let company_task = spawn {
        if (campaign.research_enabled) { research_company(contact.company) } else { null }
    };
    let people_task = spawn {
        if (campaign.people_research_enabled) {
            research_person(full_name(contact), contact.email, contact.company)
        } else {
            null
        }
    };

    let company_research = await company_task;
    let people_research = await people_task;

    let emails = generate_emails(contact, campaign, company_research, people_research);

    ProcessedContact {
        contact: contact,
        company_research: company_research,
        people_research: people_research,
        emails: emails,
    }
}
