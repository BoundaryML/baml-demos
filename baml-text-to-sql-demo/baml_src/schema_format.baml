// Pure schema-formatting logic — no LLM, no I/O. Ports the two string builders
// from the Mastra version (`createSchemaDescription`, `createSchemaPresentation`).
// Being pure BAML, they're unit-testable offline with `baml test` (see bottom).

// All columns belonging to one table (schema-qualified).
function columns_for(schema: DatabaseSchema, schema_name: string, table_name: string) -> Column[] {
    schema
        .columns
        .filter(
            (c) -> {
                c.table_schema == schema_name && c.table_name == table_name
            },
        )
}

// Row count for one table, or null if not introspected.
function row_count_for(schema: DatabaseSchema, schema_name: string, table_name: string) -> int? {
    schema
        .row_counts
        .find(
            (r) -> {
                r.schema_name == schema_name && r.table_name == table_name
            },
        )
        ?.row_count
}

// One column rendered for the LLM prompt, e.g. "  - id: integer [PRIMARY KEY] [NOT NULL]".
function describe_column(c: Column) -> string {
    let typ = if let len: int = c.character_maximum_length {
        `${c.data_type}(${len})`
    } else {
        c.data_type
    };
    let pk = if (c.is_primary_key) {
        " [PRIMARY KEY]"
    } else {
        ""
    };
    let not_null = if (c.is_nullable == "NO") {
        " [NOT NULL]"
    } else {
        ""
    };
    let dflt = if let d: string = c.column_default {
        ` [DEFAULT: ${d}]`
    } else {
        ""
    };
    `  - ${c.column_name}: ${typ}${pk}${not_null}${dflt}`
}

// Compact, LLM-facing schema description injected into the SQL-generation prompt.
function schema_to_description(schema: DatabaseSchema) -> string {
    let lines: string[] = [];
    for (let t in schema.tables) {
        let rc = row_count_for(schema, t.schema_name, t.table_name);
        let header = if let n: int = rc {
            `\nTable: ${t.schema_name}.${t.table_name} (${n} rows)`
        } else {
            `\nTable: ${t.schema_name}.${t.table_name}`
        };
        lines.push(header);
        lines.push("Columns:");
        for (let c in columns_for(schema, t.schema_name, t.table_name)) {
            lines.push(describe_column(c));
        }
    }

    if (schema.relationships.length() > 0) {
        lines.push("\nRelationships:");
        for (let r in schema.relationships) {
            lines
                .push(
                    `  - ${r.table_schema}.${r.table_name}.${r.column_name} → ${r.foreign_table_schema}.${r.foreign_table_name}.${r.foreign_column_name}`,
                );
        }
    }

    if (schema.indexes.length() > 0) {
        lines.push("\nIndexes:");
        for (let i in schema.indexes) {
            lines.push(`  - ${i.schema_name}.${i.table_name}: ${i.index_name}`);
        }
    }

    lines.join("\n")
}

// Human-readable Markdown overview shown to the user before they ask a question.
function present_schema(schema: DatabaseSchema) -> string {
    let out: string[] = [];
    out.push("# Database Schema Overview\n");
    out.push("## Summary");
    out.push(`- **Tables**: ${schema.total_tables()}`);
    out.push(`- **Columns**: ${schema.total_columns()}`);
    out.push(`- **Relationships**: ${schema.total_relationships()}`);
    out.push(`- **Indexes**: ${schema.total_indexes()}\n`);

    out.push("## Tables and Columns\n");
    for (let t in schema.tables) {
        let rc = row_count_for(schema, t.schema_name, t.table_name);
        let title = if let n: int = rc {
            `### ${t.table_name} (${n} rows)`
        } else {
            `### ${t.table_name}`
        };
        out.push(title);
        out.push("");
        out.push("| Column | Type | Nullable | Key | Default |");
        out.push("|--------|------|----------|-----|---------|");
        for (let c in columns_for(schema, t.schema_name, t.table_name)) {
            let typ = if let len: int = c.character_maximum_length {
                `${c.data_type}(${len})`
            } else {
                c.data_type
            };
            let nullable = if (c.is_nullable == "YES") {
                "✓"
            } else {
                "✗"
            };
            let key = if (c.is_primary_key) {
                "PK"
            } else {
                ""
            };
            let dflt = c.column_default ?? "";
            out.push(`| ${c.column_name} | ${typ} | ${nullable} | ${key} | ${dflt} |`);
        }
        out.push("");
    }

    if (schema.relationships.length() > 0) {
        out.push("## Relationships\n");
        for (let r in schema.relationships) {
            out.push(
                `- **${r.table_name}.${r.column_name}** → **${r.foreign_table_name}.${r.foreign_column_name}**`,
            );
        }
        out.push("");
    }

    if (schema.indexes.length() > 0) {
        out.push("## Indexes\n");
        for (let i in schema.indexes) {
            out.push(`- **${i.table_name}**: ${i.index_name}`);
        }
        out.push("");
    }

    out.push("---\n");
    out.push(
        "**Database schema introspection complete!** You can now ask questions in natural language.",
    );

    out.join("\n")
}
