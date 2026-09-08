function ReadOverride(store: string, llm_choice_key: root.LlmChoiceKey) -> root.StoredOverride {
    let directory = env.DEMO_DATA_DIR.or(".demo-data");
    let prefix = `${directory}/${store}/${llm_choice_key.function_name}`;
    let user_key = `${llm_choice_key.org}-${llm_choice_key.user}.llm-override`;
    if (llm_choice_key.user != "" && baml.fs.exists(`${prefix}/${user_key}`)) {
        return root.StoredOverride {
            source: `${llm_choice_key.function_name}/${user_key}`,
            content: baml.fs.read(`${prefix}/${user_key}`),
        };
    }
    let org_key = `${llm_choice_key.org}.llm-override`;
    if (baml.fs.exists(`${prefix}/${org_key}`)) {
        return root.StoredOverride {
            source: `${llm_choice_key.function_name}/${org_key}`,
            content: baml.fs.read(`${prefix}/${org_key}`),
        };
    }
    root.StoredOverride { source: "Application default", content: null }
}
