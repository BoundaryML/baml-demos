// The one place an LLM is actually called. The return type `GeneratedSQL` IS the
// schema the model must produce — `${ctx.output_format}` renders it into the prompt
// and the bridge parses the reply straight into a typed value. No Zod, no manual
// JSON wrangling like the Mastra `generateObject` call.

client<llm> SqlGenerator {
    provider: openai,
    options: {
        model: env.MODEL,
        api_key: env.OPENAI_API_KEY,
        // Low temperature → more deterministic SQL, matching the Mastra tool.
        temperature: 0.1,
    },
}

function GenerateSQL(natural_language_query: string, schema: DatabaseSchema) -> GeneratedSQL {
    client: SqlGenerator
    prompt: `
        You are an expert PostgreSQL query generator. Convert the natural-language
        question into an accurate SQL query.

        DATABASE SCHEMA:
        ${schema_to_description(schema)}

        RULES:
        1. Only generate SELECT queries for data retrieval.
        2. Use proper PostgreSQL syntax.
        3. Qualify column names with table names when joining tables.
        4. Use appropriate JOINs when data from multiple tables is needed.
        5. Use ILIKE for case-insensitive text searches.
        6. Use proper data types for comparisons.
        7. Format the query with clear indentation and line breaks.
        8. Include WHERE clauses to filter results where appropriate.
        9. Use LIMIT to avoid overly large result sets when appropriate.
        10. Consider the performance implications of the query.

        Analyze the question carefully: identify which tables and columns are
        needed, whether joins or aggregation are required, and how to filter,
        order, and limit the results.

        QUESTION: "${natural_language_query}"

        Provide the SQL, a clear explanation, your confidence (0.0-1.0), any
        assumptions, and the list of tables used.

        ${ctx.output_format}
    `
}

// Read-only safety gate, ported from the Mastra execution tool. Pure + offline-
// testable: the workflow refuses to run anything that isn't a read. Allows a
// leading CTE (`WITH … SELECT …`), which the model often produces for rankings.
function is_select_query(sql: string) -> bool {
    let s = sql.trim().to_lower_case();
    s.starts_with("select") || s.starts_with("with")
}
