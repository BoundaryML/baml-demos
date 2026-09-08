function DescribeLaunch(brief: root.LaunchBrief) -> string {
    `Product: ${brief.product_name}\nDescription: ${brief.description}\nAudience: ${brief.audience}\nTone: ${brief.tone}`
}

function AssembleAssets(logo: image, copy: root.AnnouncementCopy) -> root.LaunchAssets {
    root.LaunchAssets {
        logo: root.LogoAsset { base64: logo.base64(), mime_type: logo.mime_type() ?? "image/png" },
        announcement: copy,
    }
}
