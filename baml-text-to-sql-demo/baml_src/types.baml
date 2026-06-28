// Typed data model for the text-to-SQL workflow.
//
// These mirror the Zod schemas in the original Mastra port, but here they are
// the single source of truth: the SAME classes are the LLM's structured-output
// schema, the host-callable return types the Python bridge fills in, and the
// Pydantic models Python imports. One definition, typed end-to-end.

// ── Database introspection results ────────────────────────────────────────────

class Table {
    schema_name: string,
    table_name: string,
    table_owner: string,
}

class Column {
    table_schema: string,
    table_name: string,
    column_name: string,
    data_type: string,
    character_maximum_length: int?,
    numeric_precision: int?,
    numeric_scale: int?,
    is_nullable: string,
    column_default: string?,
    is_primary_key: bool,
}

class Relationship {
    table_schema: string,
    table_name: string,
    column_name: string,
    foreign_table_schema: string,
    foreign_table_name: string,
    foreign_column_name: string,
    constraint_name: string,
}

class IndexInfo {
    schema_name: string,
    table_name: string,
    index_name: string,
    index_definition: string,
}

class RowCount {
    schema_name: string,
    table_name: string,
    row_count: int,
    error: string?,
}

// The whole introspected schema. Summary counts are methods, not stored fields —
// they can't drift out of sync with the data the way the Mastra `summary` object could.
class DatabaseSchema {
    tables: Table[],
    columns: Column[],
    relationships: Relationship[],
    indexes: IndexInfo[],
    row_counts: RowCount[],

    function total_tables(self) -> int {
        self.tables.length()
    }
    function total_columns(self) -> int {
        self.columns.length()
    }
    function total_relationships(self) -> int {
        self.relationships.length()
    }
    function total_indexes(self) -> int {
        self.indexes.length()
    }
}

// ── LLM output ────────────────────────────────────────────────────────────────

// The return type of GenerateSQL — i.e. the schema the model is forced to produce.
class GeneratedSQL {
    sql: string @description("The generated SQL query (SELECT only)"),
    explanation: string @description("Plain-English explanation of what the query does"),
    confidence: float @description("Confidence in the query, 0.0 to 1.0"),
    assumptions: string[] @description("Any assumptions made while writing the query"),
    tables_used: string[] @description("Tables referenced by the query"),
}

// ── Bridge I/O results (filled by the Python host callables) ──────────────────

class ExecutionResult {
    success: bool,
    data: string @description("Result rows as a JSON-encoded array; '[]' when none"),
    row_count: int,
    executed_query: string,
    error: string?,
}

class SeedResult {
    success: bool,
    message: string,
    record_count: int,
    tables_created: string[],
}

// ── Final workflow output ─────────────────────────────────────────────────────

class WorkflowResult {
    success: bool,
    natural_language_query: string,
    schema_presentation: string,
    generated: GeneratedSQL,
    execution: ExecutionResult,
    error: string?,
}
