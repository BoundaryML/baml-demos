// Codegen for the Python host: `baml generate` emits the typed `baml_sdk`
// package into demo/, next to the Python scripts that import it (so no
// sys.path tweaking). Re-run after changing any function or type that
// Python imports. NOTE: output_dir is relative to the project root (where
// baml.toml lives), not to baml_src/.
generator target {
    output_type: "python/pydantic",
    output_dir: "demo",
    default_client_mode: "sync",
    // the python/pydantic generator only supports preserve-case
    naming_convention: "preserve-case",
}
