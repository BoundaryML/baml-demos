// The orchestration that the Mastra `databaseQueryWorkflow` expressed across five
// `createStep` definitions, here as one typed BAML function. The I/O steps
// (introspect, execute) are HOST CALLABLES: Python passes in psycopg-backed
// closures, BAML drives the AI + control flow and calls back for data. Secrets
// (the connection) stay in Python; BAML never sees them.

function run_text_to_sql(
    natural_language_query: string,
    introspect: () -> DatabaseSchema,
    execute: (string) -> ExecutionResult,
) -> WorkflowResult {
    // Step 1 — introspect the live database (Python/psycopg).
    let schema = introspect();
    let presentation = present_schema(schema);
    log.info(presentation);

    // Step 2 — natural language -> SQL (the LLM call).
    let generated = GenerateSQL(natural_language_query, schema);
    log.info(`Generated SQL (confidence ${generated.confidence}):\n${generated.sql}`);

    // Step 3 — SELECT-only safety gate before anything touches the database.
    if (!is_select_query(generated.sql)) {
        let denied = "Only SELECT queries are allowed for security reasons";
        return WorkflowResult {
            success: false,
            natural_language_query: natural_language_query,
            schema_presentation: presentation,
            generated: generated,
            execution: ExecutionResult {
                success: false,
                data: "[]",
                row_count: 0,
                executed_query: generated.sql,
                error: denied,
            },
            error: denied,
        };
    }

    // Step 4 — execute the approved query (Python/psycopg) and return everything.
    let execution = execute(generated.sql);
    WorkflowResult {
        success: execution.success,
        natural_language_query: natural_language_query,
        schema_presentation: presentation,
        generated: generated,
        execution: execution,
        error: execution.error,
    }
}

// ── Offline tests for the pure logic (no model, no database) ───────────────────

test "select-only safety gate" {
    assert.is_true(is_select_query("SELECT * FROM cities"));
    assert.is_true(is_select_query("  select 1"));
    assert.is_true(is_select_query("WITH t AS (SELECT 1) SELECT * FROM t"));
    assert.is_true(!is_select_query("DELETE FROM cities"));
    assert.is_true(!is_select_query("drop table cities"))
}

test "schema formatting (pure, no model call)" {
    let schema = DatabaseSchema {
        tables: [Table { schema_name: "public", table_name: "cities", table_owner: "postgres" }],
        columns: [
            Column {
                table_schema: "public",
                table_name: "cities",
                column_name: "id",
                data_type: "integer",
                character_maximum_length: null,
                numeric_precision: 32,
                numeric_scale: 0,
                is_nullable: "NO",
                column_default: null,
                is_primary_key: true,
            },
            Column {
                table_schema: "public",
                table_name: "cities",
                column_name: "name",
                data_type: "character varying",
                character_maximum_length: 255,
                numeric_precision: null,
                numeric_scale: null,
                is_nullable: "YES",
                column_default: null,
                is_primary_key: false,
            },
        ],
        relationships: [],
        indexes: [],
        row_counts: [RowCount { schema_name: "public", table_name: "cities", row_count: 42, error: null }],
    };

    assert.equal(schema.total_tables(), 1);
    assert.equal(schema.total_columns(), 2);

    let desc = schema_to_description(schema);
    assert.contains(desc, "Table: public.cities (42 rows)");
    assert.contains(desc, "- id: integer [PRIMARY KEY] [NOT NULL]");
    assert.contains(desc, "- name: character varying(255)");

    let md = present_schema(schema);
    assert.contains(md, "### cities (42 rows)");
    assert.contains(md, "| id | integer | ✗ | PK |")
}
