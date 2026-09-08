// Demo 5: independent WorkOS flags supply the two model choices.
function GenerateLogo(brief: root.LaunchBrief) -> image {
    client: root.shared.DefaultLogo
    prompt: `
        Create a polished original logo for this product launch. Use a clean centered symbol with a tasteful wordmark, strong silhouette, generous negative space, and a plain light background. Deliver a finished square logo image, not a mockup or photograph. The wordmark must spell the product name exactly. Do not copy an existing brand.
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAnnouncementCopy(brief: root.LaunchBrief) -> root.AnnouncementCopy {
    client: root.shared.DefaultCopy
    prompt: `
        Write launch-ready marketing copy for this product: a compelling headline, a short tagline, a concise announcement of 80–120 words, and one clear call to action. Stay faithful to the brief; invent no dates, prices, metrics, or endorsements.
            ${ctx.output_format()}
            ${root.shared.DescribeLaunch(brief)}
    `
}

function GenerateAssets(
    brief: root.LaunchBrief,
    logo: root.ModelChoice,
    copy: root.ModelChoice,
) -> root.LaunchAssets {
    //# WorkOS flags are evaluated by the server before invoking this workflow
    let logo_client = root.shared.MakeClient("GenerateLogo", logo);
    let copy_client = root.shared.MakeClient("GenerateAnnouncementCopy", copy);
    let logo_asset = spawn { GenerateLogo(brief, client = logo_client) };
    let announcement = spawn { GenerateAnnouncementCopy(brief, client = copy_client) };
    root.shared.AssembleAssets(await logo_asset, await announcement)
}
