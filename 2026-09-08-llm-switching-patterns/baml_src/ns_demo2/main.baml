// Demo 2: each function reads its deployment settings.
function GenerateLogo(brief: root.LaunchBrief) -> image {
    client: EnvironmentClient("GenerateLogo")
    prompt: `
        Create a polished original logo for this product launch. Use a clean centered symbol with a tasteful wordmark, strong silhouette, generous negative space, and a plain light background. Deliver a finished square logo image, not a mockup or photograph. The wordmark must spell the product name exactly. Do not copy an existing brand.
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAnnouncementCopy(brief: root.LaunchBrief) -> root.AnnouncementCopy {
    client: EnvironmentClient("GenerateAnnouncementCopy")
    prompt: `
        Write launch-ready marketing copy for this product: a compelling headline, a short tagline, a concise announcement of 80–120 words, and one clear call to action. Stay faithful to the brief; invent no dates, prices, metrics, or endorsements.
            ${ctx.output_format()}
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAssets(brief: root.LaunchBrief) -> root.LaunchAssets {
    //# Generate both assets with this demo's LLM functions
    let logo = spawn { GenerateLogo(brief) };
    let copy = spawn { GenerateAnnouncementCopy(brief) };
    root.shared.AssembleAssets(await logo, await copy)
}

function EnvironmentModel(function_name: root.AssetFunction) -> root.ModelChoice {
    if (function_name == "GenerateLogo") {
        root.ModelChoice {
            provider: env.LOGO_LLM_PROVIDER.or("google"),
            model: env.LOGO_LLM_MODEL.or("gemini-3.1-flash-image"),
        }
    } else {
        root.ModelChoice {
            provider: env.COPY_LLM_PROVIDER.or("openai"),
            model: env.COPY_LLM_MODEL.or("gpt-5.2"),
        }
    }
}

function EnvironmentClient(function_name: root.AssetFunction) -> ai.Client {
    root.shared.MakeClient(function_name, EnvironmentModel(function_name))
}
