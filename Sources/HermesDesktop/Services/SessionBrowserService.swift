import Foundation

final class SessionBrowserService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func listSessions(
        connection: ConnectionProfile,
        offset: Int,
        limit: Int
    ) async throws -> SessionListPage {
        let script = try RemotePythonScript.wrap(
            SessionPageRequest(offset: offset, limit: limit),
            body: sessionListBody
        )

        return try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SessionListPage.self
        )
    }

    func loadTranscript(
        connection: ConnectionProfile,
        sessionID: String
    ) async throws -> [SessionMessage] {
        let script = try RemotePythonScript.wrap(
            SessionDetailRequest(sessionID: sessionID),
            body: sessionDetailBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SessionDetailResponse.self
        )

        return response.items
    }

    private var sessionListBody: String {
        sharedSessionHelpers + """

        request = payload
        context = None

        try:
            context = try_open_store()

            if context is None:
                items = build_jsonl_session_summaries()
                if not items:
                    fail("No readable SQLite session store was discovered under ~/.hermes, and no JSONL session artifacts were found under ~/.hermes/sessions.")
            else:
                session_rows = context["connection"].execute(
                    f"SELECT * FROM {quote_ident(context['session_table'])}"
                ).fetchall()

                items = []
                for row in session_rows:
                    record = dict(zip(context["session_columns"], row))

                    session_id = stringify(record.get(context["session_id_column"]))
                    if not session_id:
                        continue

                    if context["message_timestamp_column"]:
                        stats = context["connection"].execute(
                            f"SELECT COUNT(*), MAX({quote_ident(context['message_timestamp_column'])}) "
                            f"FROM {quote_ident(context['message_table'])} "
                            f"WHERE {quote_ident(context['message_session_id_column'])} = ?",
                            (session_id,)
                        ).fetchone()
                    else:
                        stats = context["connection"].execute(
                            f"SELECT COUNT(*), NULL "
                            f"FROM {quote_ident(context['message_table'])} "
                            f"WHERE {quote_ident(context['message_session_id_column'])} = ?",
                            (session_id,)
                        ).fetchone()

                    if context["session_message_count_column"] and record.get(context["session_message_count_column"]) is not None:
                        message_count = int(record.get(context["session_message_count_column"]))
                    else:
                        message_count = int(stats[0]) if stats and stats[0] is not None else None
                    last_active = stats[1] if stats and stats[1] is not None else record.get(context["session_started_column"])

                    preview = None
                    if context["message_content_column"]:
                        preview_query = (
                            f"SELECT {quote_ident(context['message_content_column'])} "
                            f"FROM {quote_ident(context['message_table'])} "
                            f"WHERE {quote_ident(context['message_session_id_column'])} = ? "
                        )
                        preview_args = [session_id]
                        if context["message_role_column"]:
                            preview_query += f"AND {quote_ident(context['message_role_column'])} IN ('user', 'assistant', 'system') "
                        preview_query += "ORDER BY "
                        if context["message_timestamp_column"]:
                            preview_query += f"{quote_ident(context['message_timestamp_column'])}, "
                        preview_query += f"{quote_ident(context['message_id_column'])} LIMIT 1"

                        preview_row = context["connection"].execute(preview_query, tuple(preview_args)).fetchone()
                        if preview_row and preview_row[0] is not None:
                            preview = sanitize_preview(stringify(preview_row[0]))[:120]

                    title = None
                    if context["session_title_column"]:
                        title = sanitize_title(record.get(context["session_title_column"]))
                    if title is None and preview:
                        title = preview[:80]

                    items.append({
                        "id": session_id,
                        "title": title,
                        "started_at": normalize_json_value(record.get(context["session_started_column"])),
                        "last_active": normalize_json_value(last_active),
                        "message_count": message_count,
                        "preview": preview,
                    })

                items.sort(key=lambda item: sort_key(item.get("last_active") or item.get("started_at")), reverse=True)

            start = int(request.get("offset", 0))
            end = start + int(request.get("limit", 50))

            print(json.dumps({
                "ok": True,
                "total_count": len(items),
                "items": items[start:end],
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to read the remote Hermes session list: {exc}")
        finally:
            try:
                if context and context.get("connection"):
                    context["connection"].close()
            except Exception:
                pass
        """
    }

    private var sessionDetailBody: String {
        sharedSessionHelpers + """

        request = payload
        context = None

        try:
            context = try_open_store()

            if context is None:
                items = load_jsonl_transcript(request["session_id"])
            else:
                query = (
                    f"SELECT * FROM {quote_ident(context['message_table'])} "
                    f"WHERE {quote_ident(context['message_session_id_column'])} = ? "
                    "ORDER BY "
                )

                if context["message_timestamp_column"]:
                    query += f"{quote_ident(context['message_timestamp_column'])}, "
                query += quote_ident(context["message_id_column"])

                rows = context["connection"].execute(
                    query,
                    (request["session_id"],)
                ).fetchall()

                items = []
                for row in rows:
                    record = dict(zip(context["message_columns"], row))
                    metadata = {}
                    for key, value in record.items():
                        if key in {
                            context["message_id_column"],
                            context["message_session_id_column"],
                            context["message_role_column"],
                            context["message_content_column"],
                            context["message_timestamp_column"],
                        }:
                            continue
                        metadata[key] = normalize_json_value(value)

                    items.append({
                        "id": stringify(record.get(context["message_id_column"])) or str(len(items) + 1),
                        "role": stringify(record.get(context["message_role_column"])) if context["message_role_column"] else None,
                        "content": extract_record_content(record),
                        "timestamp": normalize_json_value(record.get(context["message_timestamp_column"])) if context["message_timestamp_column"] else None,
                        "metadata": metadata or None,
                    })

            print(json.dumps({
                "ok": True,
                "items": items,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to read the remote Hermes transcript: {exc}")
        finally:
            try:
                if context and context.get("connection"):
                    context["connection"].close()
            except Exception:
                pass
        """
    }

    private var sharedSessionHelpers: String {
        """
        import json
        import os
        import pathlib
        import sqlite3
        import sys
        import datetime
        import re

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
            return '"' + value.replace('"', '""') + '"'

        def stringify(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            return str(value)

        def normalize_json_value(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            if isinstance(value, dict):
                return {
                    stringify(key) or "key": normalize_json_value(item)
                    for key, item in value.items()
                }
            if isinstance(value, (list, tuple)):
                return [normalize_json_value(item) for item in value]
            if isinstance(value, (str, int, float, bool)):
                return value
            return str(value)

        def sort_key(value):
            if value is None:
                return -1
            if isinstance(value, (int, float)):
                return float(value)
            try:
                return float(value)
            except Exception:
                return str(value)

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def sanitize_preview(text):
            if text is None:
                return None
            return text.replace("\\n", " ").replace("\\r", " ").strip()

        def sanitize_title(value):
            text = sanitize_preview(stringify(value))
            if text is None or not text:
                return None
            if text.lower().startswith("<think>"):
                return None
            return text[:120]

        def parse_timestamp_value(value):
            if value is None:
                return None
            if isinstance(value, (int, float)):
                return float(value)

            value = stringify(value)
            if value is None:
                return None

            try:
                return float(value)
            except Exception:
                pass

            normalized = value.replace("Z", "+00:00")
            try:
                return datetime.datetime.fromisoformat(normalized).timestamp()
            except Exception:
                return value

        def filename_timestamp(path):
            match = re.match(r"^(\\d{8})_(\\d{6})", path.stem)
            if not match:
                return None
            try:
                return datetime.datetime.strptime(match.group(1) + match.group(2), "%Y%m%d%H%M%S").timestamp()
            except Exception:
                return None

        def extract_record_content(record):
            content = record.get("content")
            if content in (None, "") and record.get("reasoning") is not None:
                content = record.get("reasoning")
            if content in (None, "") and record.get("tool_calls") is not None:
                content = record.get("tool_calls")

            if content is None:
                return None

            if isinstance(content, (dict, list, tuple)):
                return json.dumps(content, ensure_ascii=False)

            return stringify(content)

        def iter_session_store_candidates(hermes_home):
            seen = set()

            def emit(candidate):
                resolved = str(candidate)
                if resolved in seen or not candidate.is_file():
                    return None
                seen.add(resolved)
                return candidate

            preferred = [
                hermes_home / "state.db",
                hermes_home / "state.sqlite",
                hermes_home / "state.sqlite3",
                hermes_home / "store.db",
                hermes_home / "store.sqlite",
                hermes_home / "store.sqlite3",
            ]

            for candidate in preferred:
                candidate = emit(candidate)
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
                candidate = emit(candidate)
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
                    candidate = emit(candidate)
                    if candidate is not None:
                        yield candidate

        def discover_jsonl_artifacts():
            sessions_dir = pathlib.Path.home() / ".hermes" / "sessions"
            if not sessions_dir.exists():
                return []

            return sorted(
                [item for item in sessions_dir.rglob("*.jsonl") if item.is_file()],
                key=lambda item: item.stat().st_mtime,
                reverse=True,
            )

        def discover_store():
            home = pathlib.Path.home()
            hermes_home = home / ".hermes"
            if not hermes_home.exists():
                return None, None, None

            for candidate in iter_session_store_candidates(hermes_home):
                try:
                    connection = sqlite3.connect(f"file:{candidate}?mode=ro", uri=True)
                    connection.execute("PRAGMA busy_timeout = 2000")
                    tables = [row[0] for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                    ).fetchall()]
                    session_table = choose_table(tables, "sessions")
                    message_table = choose_table(tables, "messages")
                    if session_table and message_table:
                        return connection, session_table, message_table
                    connection.close()
                except Exception:
                    continue
            return None, None, None

        def try_open_store():
            connection, session_table, message_table = discover_store()
            if not connection:
                return None

            session_columns = [row[1] for row in connection.execute(
                f"PRAGMA table_info({quote_ident(session_table)})"
            ).fetchall()]
            message_columns = [row[1] for row in connection.execute(
                f"PRAGMA table_info({quote_ident(message_table)})"
            ).fetchall()]

            session_id_column = choose_column(session_columns, ["id", "session_id"])
            session_title_column = choose_column(session_columns, ["title", "summary", "name"])
            session_started_column = choose_column(session_columns, ["started_at", "created_at", "timestamp"])
            session_message_count_column = choose_column(session_columns, ["message_count"])
            session_parent_column = choose_column(session_columns, ["parent_session_id", "parent_id"])

            message_id_column = choose_column(message_columns, ["id", "message_id"])
            message_session_id_column = choose_column(message_columns, ["session_id", "conversation_id"])
            message_role_column = choose_column(message_columns, ["role", "sender", "author"])
            message_content_column = choose_column(message_columns, ["content", "text", "body"])
            message_timestamp_column = choose_column(message_columns, ["timestamp", "created_at", "time"])

            missing = [
                name for name, value in [
                    ("session id", session_id_column),
                    ("message id", message_id_column),
                    ("message session id", message_session_id_column),
                ] if value is None
            ]

            if missing:
                fail("Unsupported session schema: missing " + ", ".join(missing))

            return {
                "connection": connection,
                "session_table": session_table,
                "message_table": message_table,
                "session_columns": session_columns,
                "message_columns": message_columns,
                "session_id_column": session_id_column,
                "session_title_column": session_title_column,
                "session_started_column": session_started_column,
                "session_message_count_column": session_message_count_column,
                "session_parent_column": session_parent_column,
                "message_id_column": message_id_column,
                "message_session_id_column": message_session_id_column,
                "message_role_column": message_role_column,
                "message_content_column": message_content_column,
                "message_timestamp_column": message_timestamp_column,
            }

        def build_jsonl_session_summaries():
            items = []

            for path in discover_jsonl_artifacts():
                started_at = filename_timestamp(path) or path.stat().st_mtime
                last_active = started_at
                message_count = 0
                preview = None
                title = None

                try:
                    with path.open("r", encoding="utf-8") as handle:
                        for line in handle:
                            line = line.strip()
                            if not line:
                                continue

                            try:
                                record = json.loads(line)
                            except Exception:
                                continue

                            if not isinstance(record, dict):
                                continue

                            role = stringify(record.get("role"))
                            timestamp = parse_timestamp_value(record.get("timestamp"))
                            if timestamp is not None:
                                if started_at is None:
                                    started_at = timestamp
                                last_active = timestamp

                            content = sanitize_preview(extract_record_content(record))
                            if role != "session_meta":
                                message_count += 1

                            if preview is None and content:
                                preview = content[:120]

                            if title is None and role in ("user", "assistant", "system") and content:
                                title = sanitize_title(content[:80])
                except Exception:
                    continue

                items.append({
                    "id": path.stem,
                    "title": title or path.stem,
                    "started_at": normalize_json_value(started_at),
                    "last_active": normalize_json_value(last_active or path.stat().st_mtime),
                    "message_count": message_count,
                    "preview": preview,
                })

            items.sort(key=lambda item: sort_key(item.get("last_active") or item.get("started_at")), reverse=True)
            return items

        def load_jsonl_transcript(session_id):
            artifact = None
            for path in discover_jsonl_artifacts():
                if path.stem == session_id:
                    artifact = path
                    break

            if artifact is None:
                fail(f"No JSONL transcript artifact was found for session '{session_id}'.")

            items = []
            with artifact.open("r", encoding="utf-8") as handle:
                for index, line in enumerate(handle, start=1):
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        record = json.loads(line)
                    except Exception:
                        continue

                    if not isinstance(record, dict):
                        continue

                    role = stringify(record.get("role")) or "event"
                    if role == "session_meta":
                        continue

                    metadata = {}
                    for key, value in record.items():
                        if key in {"role", "content", "timestamp"}:
                            continue
                        metadata[key] = normalize_json_value(value)

                    items.append({
                        "id": str(index),
                        "role": role,
                        "content": extract_record_content(record),
                        "timestamp": normalize_json_value(parse_timestamp_value(record.get("timestamp"))),
                        "metadata": metadata or None,
                    })

            return items
        """
    }
}

private struct SessionPageRequest: Encodable {
    let offset: Int
    let limit: Int
}

private struct SessionDetailRequest: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}
