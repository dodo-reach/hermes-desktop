import Foundation

final class UsageBrowserService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func loadUsage(
        connection: ConnectionProfile,
        hintedSessionStore: RemoteSessionStore?
    ) async throws -> UsageSummary {
        let script = try RemotePythonScript.wrap(
            UsageSummaryRequest(
                hintedStorePath: hintedSessionStore?.path,
                hintedSessionTable: hintedSessionStore?.sessionTable
            ),
            body: usageSummaryBody
        )

        return try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: UsageSummary.self
        )
    }

    private var usageSummaryBody: String {
        """
        import json
        import pathlib
        import sqlite3
        import sys

        def choose_table(tables, needle):
            lowered = needle.lower()
            for name in tables:
                if name.lower() == lowered:
                    return name
            for name in tables:
                if lowered in name.lower():
                    return name
            return None

        def choose_column(columns, choices):
            lowered = {column.lower(): column for column in columns}
            for choice in choices:
                if choice.lower() in lowered:
                    return lowered[choice.lower()]
            for choice in choices:
                for column in columns:
                    if choice.lower() in column.lower():
                        return column
            return None

        def quote_ident(value):
            return '"' + str(value).replace('"', '""') + '"'

        def quote_text(value):
            return "'" + str(value).replace("'", "''") + "'"

        def stringify(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            return str(value)

        def sanitize_title(value):
            text = stringify(value)
            if text is None:
                return None
            text = text.replace("\\n", " ").replace("\\r", " ").strip()
            if not text:
                return None
            if text.lower().startswith("<think>"):
                return None
            return text[:120]

        def tilde(path, home):
            try:
                relative = path.relative_to(home)
                return "~/" + relative.as_posix() if relative.as_posix() != "." else "~"
            except ValueError:
                return path.as_posix()

        def expand_remote_path(value, home):
            if not value:
                return None
            if value == "~":
                return home
            if value.startswith("~/"):
                return home / value[2:]
            return pathlib.Path(value)

        def emit_candidate(candidate, seen):
            if candidate is None:
                return None
            resolved = str(candidate)
            if resolved in seen or not candidate.is_file():
                return None
            seen.add(resolved)
            return candidate

        def iter_session_store_candidates(hermes_home, home, hinted_path):
            seen = set()

            hinted_candidate = emit_candidate(expand_remote_path(hinted_path, home), seen)
            if hinted_candidate is not None:
                yield hinted_candidate

            preferred = [
                hermes_home / "state.db",
                hermes_home / "state.sqlite",
                hermes_home / "state.sqlite3",
                hermes_home / "store.db",
                hermes_home / "store.sqlite",
                hermes_home / "store.sqlite3",
            ]

            for candidate in preferred:
                candidate = emit_candidate(candidate, seen)
                if candidate is not None:
                    yield candidate

            for candidate in sorted(
                [
                    item
                    for pattern in ("*.db", "*.sqlite", "*.sqlite3")
                    for item in hermes_home.glob(pattern)
                    if item.is_file()
                ],
                key=lambda item: item.stat().st_mtime,
                reverse=True,
            ):
                candidate = emit_candidate(candidate, seen)
                if candidate is not None:
                    yield candidate

            sessions_dir = hermes_home / "sessions"
            if sessions_dir.exists():
                for candidate in sorted(
                    [
                        item
                        for pattern in ("*.db", "*.sqlite", "*.sqlite3")
                        for item in sessions_dir.rglob(pattern)
                        if item.is_file()
                    ],
                    key=lambda item: item.stat().st_mtime,
                    reverse=True,
                ):
                    candidate = emit_candidate(candidate, seen)
                    if candidate is not None:
                        yield candidate

        def discover_session_store(hermes_home, home, hinted_path, hinted_session_table):
            for candidate in iter_session_store_candidates(hermes_home, home, hinted_path):
                connection = None
                try:
                    connection = sqlite3.connect(f"file:{candidate}?mode=ro", uri=True)
                    tables = [
                        row[0]
                        for row in connection.execute(
                            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                        ).fetchall()
                    ]

                    session_table = None
                    if hinted_session_table:
                        for table in tables:
                            if table.lower() == hinted_session_table.lower():
                                session_table = table
                                break

                    if session_table is None:
                        session_table = choose_table(tables, "sessions")

                    if session_table:
                        return {
                            "resolved_path": str(candidate),
                            "display_path": tilde(candidate, home),
                            "session_table": session_table,
                        }
                except Exception:
                    pass
                finally:
                    try:
                        if connection is not None:
                            connection.close()
                    except Exception:
                        pass

            return None

        def unavailable(message):
            print(json.dumps({
                "ok": True,
                "state": "unavailable",
                "session_count": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "top_sessions": [],
                "recent_sessions": [],
                "database_path": None,
                "session_table": None,
                "message": message,
                "missing_columns": [],
            }, ensure_ascii=False))

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        request = payload

        try:
            home = pathlib.Path.home()
            hermes_home = home / ".hermes"

            store = discover_session_store(
                hermes_home,
                home,
                request.get("hinted_store_path"),
                request.get("hinted_session_table"),
            )

            if store is None:
                unavailable("No readable Hermes SQLite session store with a sessions table was discovered on the active host.")
                sys.exit(0)

            connection = sqlite3.connect(f"file:{store['resolved_path']}?mode=ro", uri=True)

            try:
                columns = [
                    row[1]
                    for row in connection.execute(
                        f"PRAGMA table_info({quote_text(store['session_table'])})"
                    ).fetchall()
                ]

                lowered_columns = {column.lower(): column for column in columns}
                session_id_column = choose_column(columns, ["id", "session_id"])
                session_title_column = choose_column(columns, ["title", "summary", "name"])
                session_started_column = choose_column(columns, ["started_at", "created_at", "timestamp"])
                missing_columns = []

                if "input_tokens" in lowered_columns:
                    input_expression = f"COALESCE(SUM({quote_ident(lowered_columns['input_tokens'])}), 0)"
                    input_value_expression = f"COALESCE({quote_ident(lowered_columns['input_tokens'])}, 0)"
                else:
                    input_expression = "0"
                    input_value_expression = "0"
                    missing_columns.append("input_tokens")

                if "output_tokens" in lowered_columns:
                    output_expression = f"COALESCE(SUM({quote_ident(lowered_columns['output_tokens'])}), 0)"
                    output_value_expression = f"COALESCE({quote_ident(lowered_columns['output_tokens'])}, 0)"
                else:
                    output_expression = "0"
                    output_value_expression = "0"
                    missing_columns.append("output_tokens")

                row = connection.execute(
                    f"SELECT COUNT(*), {input_expression}, {output_expression} "
                    f"FROM {quote_ident(store['session_table'])}"
                ).fetchone() or (0, 0, 0)

                top_sessions = []
                recent_sessions = []
                if session_id_column:
                    top_query = (
                        f"SELECT "
                        f"{quote_ident(session_id_column)}, "
                        f"{quote_ident(session_title_column) if session_title_column else 'NULL'}, "
                        f"{input_value_expression}, "
                        f"{output_value_expression}, "
                        f"({input_value_expression} + {output_value_expression}) "
                        f"FROM {quote_ident(store['session_table'])} "
                        f"ORDER BY 5 DESC"
                    )

                    if session_started_column:
                        top_query += f", {quote_ident(session_started_column)} DESC"

                    top_query += " LIMIT 5"

                    for top_row in connection.execute(top_query).fetchall():
                        session_id = stringify(top_row[0])
                        if not session_id:
                            continue

                        title = sanitize_title(top_row[1]) or session_id
                        top_sessions.append({
                            "id": session_id,
                            "title": title,
                            "input_tokens": int(top_row[2] or 0),
                            "output_tokens": int(top_row[3] or 0),
                            "total_tokens": int(top_row[4] or 0),
                        })

                    recent_query = (
                        f"SELECT "
                        f"{quote_ident(session_id_column)}, "
                        f"{quote_ident(session_title_column) if session_title_column else 'NULL'}, "
                        f"{input_value_expression}, "
                        f"{output_value_expression}, "
                        f"({input_value_expression} + {output_value_expression}) "
                        f"FROM {quote_ident(store['session_table'])} "
                    )

                    if session_started_column:
                        recent_query += f"ORDER BY {quote_ident(session_started_column)} DESC"
                    else:
                        recent_query += f"ORDER BY {quote_ident(session_id_column)} DESC"

                    recent_query += " LIMIT 100"

                    recent_rows = connection.execute(recent_query).fetchall()
                    for recent_row in reversed(recent_rows):
                        session_id = stringify(recent_row[0])
                        if not session_id:
                            continue

                        recent_sessions.append({
                            "id": session_id,
                            "title": sanitize_title(recent_row[1]) or session_id,
                            "input_tokens": int(recent_row[2] or 0),
                            "output_tokens": int(recent_row[3] or 0),
                            "total_tokens": int(recent_row[4] or 0),
                        })

                message = None
                if missing_columns:
                    joined = ", ".join(missing_columns)
                    message = f"Missing session columns are treated as 0: {joined}."

                print(json.dumps({
                    "ok": True,
                    "state": "available",
                    "session_count": int(row[0] or 0),
                    "input_tokens": int(row[1] or 0),
                    "output_tokens": int(row[2] or 0),
                    "top_sessions": top_sessions,
                    "recent_sessions": recent_sessions,
                    "database_path": store["display_path"],
                    "session_table": store["session_table"],
                    "message": message,
                    "missing_columns": missing_columns,
                }, ensure_ascii=False))
            finally:
                connection.close()
        except Exception as exc:
            fail(f"Unable to read remote Hermes usage: {exc}")
        """
    }
}

private struct UsageSummaryRequest: Encodable {
    let hintedStorePath: String?
    let hintedSessionTable: String?

    enum CodingKeys: String, CodingKey {
        case hintedStorePath = "hinted_store_path"
        case hintedSessionTable = "hinted_session_table"
    }
}
