// Demo 3: each LLM chooses by organization, user, and function.
// Callers supply identity; each LLM function attaches its own function name.
class UserContext {
    org: string,
    user: string,
}

function GenerateLogo(brief: root.LaunchBrief, user_context: root.demo3.UserContext) -> image {
    client: ChooseLlm(
        llm_choice_key = root.LlmChoiceKey {
            org: user_context.org,
            user: user_context.user,
            function_name: "GenerateLogo",
        },
    )
    prompt: `
        Create a polished original logo for this product launch. Use a clean centered symbol with a tasteful wordmark, strong silhouette, generous negative space, and a plain light background. Deliver a finished square logo image, not a mockup or photograph. Spell the product name exactly. Do not copy an existing brand.
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAnnouncementCopy(
    brief: root.LaunchBrief,
    user_context: root.demo3.UserContext,
) -> root.AnnouncementCopy {
    client: ChooseLlm(
        llm_choice_key = root.LlmChoiceKey {
            org: user_context.org,
            user: user_context.user,
            function_name: "GenerateAnnouncementCopy",
        },
    )
    prompt: `
        Write launch-ready marketing copy: a compelling headline, a short tagline, an 80–120 word announcement, and one clear call to action. Stay faithful to the brief; invent no dates, prices, metrics, or endorsements.
            ${ctx.output_format()}
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAssets(
    brief: root.LaunchBrief,
    user_context: root.demo3.UserContext,
) -> root.LaunchAssets {
    let logo = spawn { GenerateLogo(brief, user_context) };
    let copy = spawn { GenerateAnnouncementCopy(brief, user_context) };
    root.shared.AssembleAssets(await logo, await copy)
}

function DatabaseModel(llm_choice_key: root.LlmChoiceKey) -> root.ModelChoice {
    let stored = root.shared.ReadOverride("models", llm_choice_key);
    if let source: string = stored.content {
        baml.json.from_string<root.ModelChoice>(source)
    } else {
        root.shared.DefaultModel(llm_choice_key.function_name)
    }
}

function ChooseLlm(llm_choice_key: root.LlmChoiceKey) -> ai.Client {
    //# Look up {org, user, function_name} at the LLM call site
    root.shared.MakeClient(llm_choice_key.function_name, DatabaseModel(llm_choice_key))
}
