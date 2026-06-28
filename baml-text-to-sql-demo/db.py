"""PostgreSQL I/O for the text-to-SQL demo.

This is the *thin bridge*: the only code that talks to a database. Each public
method returns one of the BAML-generated Pydantic types (`DatabaseSchema`,
`ExecutionResult`), so the values flow straight back into the typed BAML
workflow as host-callable results. All AI and orchestration logic lives in
`baml_src/`, not here.

Ported from the Mastra `database-introspection-tool` and `sql-execution-tool`.
"""

from __future__ import annotations

import json
import os

import psycopg2
from psycopg2.extras import RealDictCursor

from baml_sdk import Column, DatabaseSchema, ExecutionResult, IndexInfo, Relationship, RowCount, Table

# Same generous timeouts the Mastra `pg.Client` used (milliseconds there).
_CONNECT_TIMEOUT_S = 30
_STATEMENT_TIMEOUT_MS = 60_000

# Introspection is scoped to a single schema (default 'public'). Targeting one
# schema keeps the LLM prompt focused on the user's tables and avoids dragging in
# the dozens of internal tables a managed Postgres like Supabase keeps in its
# auth/storage/realtime schemas. Override with the DB_SCHEMA env var.
DB_SCHEMA = os.environ.get("DB_SCHEMA", "public")

_TABLES_SQL = """
    SELECT schemaname AS schema_name,
           tablename  AS table_name,
           tableowner AS table_owner
    FROM pg_tables
    WHERE schemaname = %s
    ORDER BY schemaname, tablename;
"""

_COLUMNS_SQL = """
    SELECT t.table_schema,
           t.table_name,
           c.column_name,
           c.data_type,
           c.character_maximum_length,
           c.numeric_precision,
           c.numeric_scale,
           c.is_nullable,
           c.column_default,
           CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END AS is_primary_key
    FROM information_schema.tables t
    JOIN information_schema.columns c
      ON t.table_name = c.table_name AND t.table_schema = c.table_schema
    LEFT JOIN (
        SELECT ku.table_schema, ku.table_name, ku.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage ku
          ON tc.constraint_name = ku.constraint_name
        WHERE tc.constraint_type = 'PRIMARY KEY'
    ) pk
      ON c.table_schema = pk.table_schema
     AND c.table_name = pk.table_name
     AND c.column_name = pk.column_name
    WHERE t.table_schema = %s
      AND t.table_type = 'BASE TABLE'
    ORDER BY t.table_schema, t.table_name, c.ordinal_position;
"""

_RELATIONSHIPS_SQL = """
    SELECT tc.table_schema,
           tc.table_name,
           kcu.column_name,
           ccu.table_schema AS foreign_table_schema,
           ccu.table_name   AS foreign_table_name,
           ccu.column_name  AS foreign_column_name,
           tc.constraint_name
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
     AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = %s
    ORDER BY tc.table_schema, tc.table_name, kcu.column_name;
"""

_INDEXES_SQL = """
    SELECT schemaname AS schema_name,
           tablename  AS table_name,
           indexname  AS index_name,
           indexdef   AS index_definition
    FROM pg_indexes
    WHERE schemaname = %s
    ORDER BY schemaname, tablename, indexname;
"""


class Database:
    """Owns a single psycopg connection for the lifetime of a session."""

    def __init__(self, connection_string: str):
        self.conn = psycopg2.connect(connection_string, connect_timeout=_CONNECT_TIMEOUT_S)
        self.conn.autocommit = True
        with self.conn.cursor() as cur:
            cur.execute(f"SET statement_timeout = {_STATEMENT_TIMEOUT_MS}")

    def _rows(self, sql: str, params: tuple = ()) -> list[dict]:
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            return [dict(r) for r in cur.fetchall()]

    # ── Host callable: introspect() -> DatabaseSchema ─────────────────────────
    def introspect(self) -> DatabaseSchema:
        print(f"🔌 Introspecting database schema (schema='{DB_SCHEMA}')...")
        tables = [Table(**r) for r in self._rows(_TABLES_SQL, (DB_SCHEMA,))]
        columns = [Column(**r) for r in self._rows(_COLUMNS_SQL, (DB_SCHEMA,))]
        relationships = [Relationship(**r) for r in self._rows(_RELATIONSHIPS_SQL, (DB_SCHEMA,))]
        indexes = [IndexInfo(**r) for r in self._rows(_INDEXES_SQL, (DB_SCHEMA,))]

        row_counts: list[RowCount] = []
        for t in tables:
            try:
                res = self._rows(f'SELECT COUNT(*) AS row_count FROM "{t.schema_name}"."{t.table_name}";')
                row_counts.append(
                    RowCount(
                        schema_name=t.schema_name,
                        table_name=t.table_name,
                        row_count=int(res[0]["row_count"]),
                        error=None,
                    )
                )
            except Exception as e:  # noqa: BLE001 — surface per-table failures, keep going
                row_counts.append(
                    RowCount(schema_name=t.schema_name, table_name=t.table_name, row_count=0, error=str(e))
                )

        print(f"✅ Found {len(tables)} tables, {len(columns)} columns, {len(relationships)} relationships")
        return DatabaseSchema(
            tables=tables,
            columns=columns,
            relationships=relationships,
            indexes=indexes,
            row_counts=row_counts,
        )

    # ── Host callable: execute(sql) -> ExecutionResult ────────────────────────
    def execute(self, query: str) -> ExecutionResult:
        # The BAML workflow already gated on read-only; this is defence in depth.
        # Allow a leading CTE (`WITH … SELECT …`) as well as a plain SELECT.
        if not query.strip().lower().startswith(("select", "with")):
            return ExecutionResult(
                success=False,
                data="[]",
                row_count=0,
                executed_query=query,
                error="Only SELECT queries are allowed for security reasons",
            )
        try:
            print(f"⚡ Executing:\n{query}")
            rows = self._rows(query)
            return ExecutionResult(
                success=True,
                data=json.dumps(rows, default=str),
                row_count=len(rows),
                executed_query=query,
                error=None,
            )
        except Exception as e:  # noqa: BLE001
            return ExecutionResult(
                success=False,
                data="[]",
                row_count=0,
                executed_query=query,
                error=str(e),
            )

    def close(self) -> None:
        self.conn.close()
