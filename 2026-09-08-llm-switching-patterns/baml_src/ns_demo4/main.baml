// Demo 4: override files contain a complete function ChooseLlm() -> ai.Client.
// Both LLM functions choose their own client from the full request key.
function GenerateLogo(brief: root.LaunchBrief, llm_choice_key: root.LlmChoiceKey) -> image {
    client: ChooseLlm(llm_choice_key = llm_choice_key)
    prompt: `
        Create a polished original logo for this product launch. Use a clean centered symbol with a tasteful wordmark, strong silhouette, generous negative space, and a plain light background. Deliver a finished square logo image, not a mockup or photograph. Spell the product name exactly. Do not copy an existing brand.
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAnnouncementCopy(
    brief: root.LaunchBrief,
    llm_choice_key: root.LlmChoiceKey,
) -> root.AnnouncementCopy {
    client: ChooseLlm(llm_choice_key = llm_choice_key)
    prompt: `
        Write launch-ready marketing copy: a compelling headline, a short tagline, an 80–120 word announcement, and one clear call to action. Stay faithful to the brief; invent no dates, prices, metrics, or endorsements.
            ${ctx.output_format()}
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAssets(brief: root.LaunchBrief, org: string, user: string) -> root.LaunchAssets {
    let logo = spawn {
        GenerateLogo(brief, root.LlmChoiceKey { org: org, user: user, function_name: "GenerateLogo" })
    };
    let copy = spawn {
        GenerateAnnouncementCopy(
            brief,
            root.LlmChoiceKey { org: org, user: user, function_name: "GenerateAnnouncementCopy" },
        )
    };
    root.shared.AssembleAssets(await logo, await copy)
}

type LlmFactory = () -> ai.Client throws unknown;

function CompileLlmFunction(source: string) -> LlmFactory {
    let package = reflect.Package.compile({ "override.baml": source });
    package.get_function<LlmFactory>("ChooseLlm")
        ?? throw baml.errors.InvalidArgument {
        message: "The stored program must export function ChooseLlm() -> ai.Client",
    }
}

function InspectProgram(source: string) -> string {
    let choose = CompileLlmFunction(source);
    choose().id()
}

function ChooseLlm(llm_choice_key: root.LlmChoiceKey) -> ai.Client {
    let stored = root.shared.ReadOverride("programs", llm_choice_key);
    if let source: string = stored.content {
        let choose = CompileLlmFunction(source);
        choose()
    } else {
        root.shared.MakeClient(
            llm_choice_key.function_name,
            root.shared.DefaultModel(llm_choice_key.function_name),
        )
    }
}
