// Shared input and output contracts for all five demos.
type AssetFunction = "GenerateLogo" | "GenerateAnnouncementCopy";

class LaunchBrief {
    product_name: string,
    description: string,
    audience: string,
    tone: string,
}

class AnnouncementCopy {
    headline: string,
    tagline: string,
    body: string,
    call_to_action: string,
}

class LogoAsset {
    base64: string,
    mime_type: string,
}

class LaunchAssets {
    logo: LogoAsset,
    announcement: AnnouncementCopy,
}

class ModelChoice {
    provider: string,
    model: string,
}

class LlmChoiceKey {
    org: string,
    user: string,
    function_name: AssetFunction,
}

class StoredOverride {
    source: string,
    content: string?,
}
