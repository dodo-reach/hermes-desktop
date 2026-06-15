import Foundation

final class SessionBrowserService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func listSessions(
        connection: ConnectionProfile,
        offset: Int,
        limit: Int,
        query: String
    ) async throws -> SessionListPage {
        let script = try RemotePythonScript.wrap(
            SessionPageRequest(
                offset: offset,
                limit: limit,
                query: query,
                hermesHome: connection.remoteHermesHomePath
            ),
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
            SessionDetailRequest(
                sessionID: sessionID,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: sessionDetailBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SessionDetailResponse.self
        )

        return response.items
    }

    func deleteSession(
        connection: ConnectionProfile,
        sessionID: String,
        hintedSessionStore: RemoteSessionStore?
    ) async throws {
        let script = try RemotePythonScript.wrap(
            SessionDeleteRequest(
                sessionID: sessionID,
                hermesHome: connection.remoteHermesHomePath,
                hintedStorePath: hintedSessionStore?.path,
                hintedSessionTable: hintedSessionStore?.sessionTable,
                hintedMessageTable: hintedSessionStore?.messageTable
            ),
            body: sessionDeleteBody
        )

        _ = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SessionDeleteResponse.self
        )
    }

    private var sessionListBody: String {
        sharedSessionHelpers + """

        request = payload
        context = None

        try:
            context = try_open_store()
            search_query = normalize_search_text(request.get("query"))

            if context is None:
                items = build_jsonl_session_summaries(search_query)
                if not items:
                    fail(
                        f"No readable SQLite session store was discovered under {display_hermes_home()}, "
                        f"and no JSONL session artifacts were found under {display_hermes_home()}/sessions."
                    )
            else:
                items = build_sqlite_session_summaries(
                    context,
                    include_previews=search_query is not None
                )

            if search_query is not None:
                search_matches = {}
                if context is not None:
                    search_matches = build_sqlite_session_search_matches(context, search_query)

                filtered_items = []
                for item in items:
                    session_id = stringify(item.get("id"))
                    if session_id and session_id in search_matches:
                        item["search_match"] = search_matches[session_id]
                        filtered_items.append(item)
                        continue

                    if item.get("search_match") or session_matches_query(item, search_query):
                        if not item.get("search_match"):
                            metadata_match = metadata_search_match(item, search_query)
                            if metadata_match:
                                item["search_match"] = metadata_match
                        filtered_items.append(item)

                items = filtered_items

            start = int(request.get("offset", 0))
            end = start + int(request.get("limit", 50))
            page_items = items[start:end]

            if context is not None and search_query is None:
                fill_sqlite_previews(context, page_items)

            print(json.dumps({
                "ok": True,
                "total_count": len(items),
                "items": page_items,
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
            items = load_cli_export_transcript(request["session_id"])

            if items is None:
                context = try_open_store()

            if items is None and context is None:
                items = load_jsonl_transcript(request["session_id"])
            elif items is None:
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
                        normalized_value = prune_metadata_value(normalize_json_value(value))
                        if normalized_value is not None:
                            metadata[key] = normalized_value

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

    private var sessionDeleteBody: String {
        sharedSessionHelpers + """

        request = payload

        try:
            session_id = stringify(request.get("session_id"))
            if not session_id:
                fail("The session ID is required.")

            deleted_session_rows = 0
            deleted_message_rows = 0
            deleted_jsonl_artifact = False

            store_path, session_table, message_table = discover_store_location(
                request.get("hinted_store_path"),
                request.get("hinted_session_table"),
                request.get("hinted_message_table")
            )

            if store_path is not None:
                connection = sqlite3.connect(store_path)
                connection.execute("PRAGMA busy_timeout = 2000")

                try:
                    session_columns = [row[1] for row in connection.execute(
                        f"PRAGMA table_info({quote_ident(session_table)})"
                    ).fetchall()]
                    message_columns = [row[1] for row in connection.execute(
                        f"PRAGMA table_info({quote_ident(message_table)})"
                    ).fetchall()]

                    session_id_column = choose_column(session_columns, ["id", "session_id"])
                    message_session_id_column = choose_column(message_columns, ["session_id", "conversation_id"])

                    missing = [
                        name for name, value in [
                            ("session id", session_id_column),
                            ("message session id", message_session_id_column),
                        ] if value is None
                    ]

                    if missing:
                        fail("Unsupported session schema: missing " + ", ".join(missing))

                    with connection:
                        deleted_message_rows = connection.execute(
                            f"DELETE FROM {quote_ident(message_table)} "
                            f"WHERE {quote_ident(message_session_id_column)} = ?",
                            (session_id,)
                        ).rowcount

                        deleted_session_rows = connection.execute(
                            f"DELETE FROM {quote_ident(session_table)} "
                            f"WHERE {quote_ident(session_id_column)} = ?",
                            (session_id,)
                        ).rowcount
                finally:
                    connection.close()

            artifact = None
            for path in discover_jsonl_artifacts():
                if path.stem == session_id:
                    artifact = path
                    break

            if artifact is not None:
                artifact.unlink()
                deleted_jsonl_artifact = True

            if deleted_session_rows <= 0 and deleted_message_rows <= 0 and not deleted_jsonl_artifact:
                fail(f"No remote Hermes session matching '{session_id}' was found to delete.")

            print(json.dumps({
                "ok": True,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to delete the remote Hermes session: {exc}")
        """
    }

    private var sharedSessionHelpers: String {
        """
        import json
        import pathlib
        import sqlite3
        import datetime
        import re
        import subprocess

        def display_hermes_home():
            requested = stringify(payload.get("hermes_home"))
            if requested:
                return requested
            return "~/.hermes"

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

        def normalize_search_text(value):
            text = stringify(value)
            if text is None:
                return None
            text = text.strip()
            return text.casefold() if text else None

        def session_matches_query(item, query):
            for field in (item.get("id"), item.get("title"), item.get("preview")):
                text = normalize_search_text(field)
                if text is not None and query in text:
                    return True
            return False

        def metadata_search_match(item, query):
            for field in (item.get("title"), item.get("preview"), item.get("id")):
                snippet = search_snippet(field, query)
                if snippet:
                    return {
                        "match_count": 1,
                        "message_id": None,
                        "role": None,
                        "timestamp": None,
                        "snippet": snippet,
                    }
            return None

        def search_snippet(value, query, radius=80, limit=220):
            text = sanitize_preview(searchable_text(value))
            if not text:
                return None

            folded = text.casefold()
            index = folded.find(query)
            if index < 0:
                return None

            start = max(0, index - radius)
            end = min(len(text), index + len(query) + radius)
            snippet = text[start:end].strip()
            if start > 0:
                snippet = "..." + snippet
            if end < len(text):
                snippet = snippet + "..."
            if len(snippet) > limit:
                snippet = snippet[:limit - 3].rstrip() + "..."
            return snippet

        def searchable_text(value):
            if value is None:
                return None
            if isinstance(value, (dict, list, tuple)):
                return json.dumps(value, ensure_ascii=False)
            return stringify(value)

        def value_matches_query(value, query):
            text = searchable_text(value)
            if text is None:
                return False
            return query in text.casefold()

        def escape_like_pattern(value):
            return value.replace("\\\\", "\\\\\\\\").replace("%", "\\\\%").replace("_", "\\\\_")

        def is_ascii_text(value):
            try:
                value.encode("ascii")
                return True
            except Exception:
                return False

        def role_priority(role):
            normalized = normalize_search_text(role) or ""
            if normalized in ("user", "assistant"):
                return 0
            if normalized == "system":
                return 1
            return 2

        def prune_metadata_value(value):
            if value is None:
                return None
            if isinstance(value, dict):
                cleaned = {}
                for key, item in value.items():
                    normalized_item = prune_metadata_value(item)
                    if normalized_item is not None:
                        cleaned[key] = normalized_item
                return cleaned or None
            if isinstance(value, list):
                cleaned = []
                for item in value:
                    normalized_item = prune_metadata_value(item)
                    if normalized_item is not None:
                        cleaned.append(normalized_item)
                return cleaned or None
            return value

        def sort_key(value):
            if value is None:
                return (0, 0.0, "")
            if isinstance(value, (int, float)):
                return (2, float(value), "")
            try:
                return (2, float(value), "")
            except Exception:
                parsed = parse_timestamp_value(value)
                if isinstance(parsed, (int, float)):
                    return (2, float(parsed), "")
                return (1, 0.0, str(value))

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

        def sanitize_model(value):
            text = sanitize_preview(stringify(value))
            if text is None or not text:
                return None
            return text[:160]

        def extract_model_from_record(record):
            direct = sanitize_model(record.get("model") or record.get("model_name"))
            if direct:
                return direct

            metadata = record.get("metadata")
            if isinstance(metadata, dict):
                nested = sanitize_model(
                    metadata.get("model") or
                    metadata.get("model_name") or
                    metadata.get("default_model")
                )
                if nested:
                    return nested

            return None

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
            if content in (None, "") and record.get("text") is not None:
                content = record.get("text")
            if content in (None, "") and record.get("body") is not None:
                content = record.get("body")
            if content in (None, "") and record.get("reasoning") is not None:
                content = record.get("reasoning")
            if content in (None, "") and record.get("reasoning_content") is not None:
                content = record.get("reasoning_content")
            if content in (None, "") and record.get("tool_calls") is not None:
                content = record.get("tool_calls")

            if content is None:
                return None

            if isinstance(content, (dict, list, tuple)):
                return json.dumps(content, ensure_ascii=False)

            return stringify(content)

        def choose_columns(columns, choices):
            results = []
            lowered = {column.lower(): column for column in columns}

            for choice in choices:
                exact = lowered.get(choice.lower())
                if exact and exact not in results:
                    results.append(exact)

            for choice in choices:
                needle = choice.lower()
                for column in columns:
                    if needle in column.lower() and column not in results:
                        results.append(column)

            return results

        def extract_record_search_texts(record, context):
            texts = []
            seen = set()

            def append(value):
                text = searchable_text(value)
                if text is None:
                    return
                if text in seen:
                    return
                seen.add(text)
                texts.append(text)

            display_content = extract_record_content(record)
            append(display_content)

            if display_content in (None, ""):
                for column in context.get("message_search_columns") or []:
                    append(record.get(column))

            return texts

        def build_sqlite_session_search_matches(context, query):
            search_columns = context.get("message_search_columns") or []
            if not search_columns:
                return {}

            search_sql = f"SELECT * FROM {quote_ident(context['message_table'])}"
            args = ()
            if is_ascii_text(query):
                where = " OR ".join(
                    f"CAST({quote_ident(column)} AS TEXT) COLLATE NOCASE LIKE ? ESCAPE '\\\\'"
                    for column in search_columns
                )
                args = tuple([f"%{escape_like_pattern(query)}%"] * len(search_columns))
                search_sql += f" WHERE {where}"

            search_sql += " ORDER BY "
            if context["message_timestamp_column"]:
                search_sql += f"{quote_ident(context['message_timestamp_column'])}, "
            search_sql += quote_ident(context["message_id_column"])
            rows = context["connection"].execute(search_sql, args)

            matches = {}
            for row in rows:
                record = dict(zip(context["message_columns"], row))
                session_id = stringify(record.get(context["message_session_id_column"]))
                if not session_id:
                    continue

                matched_text = None
                for text in extract_record_search_texts(record, context):
                    if value_matches_query(text, query):
                        matched_text = text
                        break

                if matched_text is None:
                    continue

                role = stringify(record.get(context["message_role_column"])) if context["message_role_column"] else None
                timestamp = normalize_json_value(record.get(context["message_timestamp_column"])) if context["message_timestamp_column"] else None
                message_id = stringify(record.get(context["message_id_column"])) or None
                snippet = search_snippet(matched_text, query)
                priority = role_priority(role)

                existing = matches.get(session_id)
                if existing is None:
                    matches[session_id] = {
                        "match_count": 1,
                        "message_id": message_id,
                        "role": role,
                        "timestamp": timestamp,
                        "snippet": snippet,
                        "_priority": priority,
                    }
                    continue

                existing["match_count"] += 1
                if priority < existing.get("_priority", 99):
                    existing["message_id"] = message_id
                    existing["role"] = role
                    existing["timestamp"] = timestamp
                    existing["snippet"] = snippet
                    existing["_priority"] = priority

            for match in matches.values():
                match.pop("_priority", None)

            return matches

        def message_item_from_record(record, fallback_id):
            metadata = {}
            for key, value in record.items():
                if key in {"id", "session_id", "role", "content", "timestamp"}:
                    continue
                normalized_value = prune_metadata_value(normalize_json_value(value))
                if normalized_value is not None:
                    metadata[key] = normalized_value

            return {
                "id": stringify(record.get("id")) or str(fallback_id),
                "role": stringify(record.get("role")) or "event",
                "content": extract_record_content(record),
                "timestamp": normalize_json_value(record.get("timestamp")),
                "metadata": metadata or None,
            }

        def load_cli_export_transcript(session_id):
            session_id = stringify(session_id)
            if not session_id:
                return None

            hermes_bin = find_hermes_binary(request)
            if not hermes_bin:
                return None

            env = os.environ.copy()
            env["HERMES_HOME"] = str(resolved_hermes_home(request))
            try:
                result = subprocess.run(
                    [hermes_bin, "sessions", "export", "-", "--session-id", session_id],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=env,
                    timeout=45,
                )
            except Exception:
                return None

            if result.returncode != 0:
                return None

            exported_records = []
            for raw_line in result.stdout.splitlines():
                line = raw_line.strip()
                if not line or not line.startswith("{"):
                    continue
                try:
                    record = json.loads(line)
                except Exception:
                    continue
                if isinstance(record, dict):
                    exported_records.append(record)

            if not exported_records:
                return None

            message_records = []
            for record in exported_records:
                messages = record.get("messages")
                if isinstance(messages, list):
                    message_records.extend([item for item in messages if isinstance(item, dict)])
                elif "role" in record or "content" in record:
                    message_records.append(record)

            if not message_records:
                return []

            return [
                message_item_from_record(record, index)
                for index, record in enumerate(message_records, start=1)
            ]

        def build_sqlite_message_stats(context):
            stats = {}
            timestamp_expr = (
                f"MAX({quote_ident(context['message_timestamp_column'])})"
                if context["message_timestamp_column"] else
                "NULL"
            )
            query = (
                f"SELECT {quote_ident(context['message_session_id_column'])}, "
                f"COUNT(*), {timestamp_expr} "
                f"FROM {quote_ident(context['message_table'])} "
                f"GROUP BY {quote_ident(context['message_session_id_column'])}"
            )

            for session_id, message_count, last_active in context["connection"].execute(query):
                normalized_session_id = stringify(session_id)
                if not normalized_session_id:
                    continue
                stats[normalized_session_id] = {
                    "message_count": int(message_count) if message_count is not None else None,
                    "last_active": last_active,
                }

            return stats

        def sqlite_preview_for_session(context, session_id):
            if not context["message_content_column"]:
                return None

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
                return sanitize_preview(stringify(preview_row[0]))[:120]
            return None

        def fill_sqlite_previews(context, items):
            for item in items:
                if item.get("preview"):
                    continue

                session_id = stringify(item.get("id"))
                if not session_id:
                    continue

                preview = sqlite_preview_for_session(context, session_id)
                if not preview:
                    continue

                item["preview"] = preview
                if not item.get("title"):
                    item["title"] = preview[:80]

        def build_sqlite_session_summaries(context, include_previews=False):
            session_rows = context["connection"].execute(
                f"SELECT * FROM {quote_ident(context['session_table'])}"
            ).fetchall()
            message_stats = build_sqlite_message_stats(context)
            records = [dict(zip(context["session_columns"], row)) for row in session_rows]
            parent_by_id = {}
            explicit_lineage_by_id = {}
            for record in records:
                session_id = stringify(record.get(context["session_id_column"]))
                if not session_id:
                    continue
                parent = stringify(record.get(context["session_parent_column"]))
                if parent:
                    parent_by_id[session_id] = parent
                lineage = stringify(record.get(context["session_lineage_column"]))
                if lineage:
                    explicit_lineage_by_id[session_id] = lineage

            def lineage_root_for(session_id, seen=None):
                if not session_id:
                    return None
                if session_id in explicit_lineage_by_id:
                    return explicit_lineage_by_id[session_id]
                if seen is None:
                    seen = set()
                if session_id in seen:
                    return None
                seen.add(session_id)
                parent = parent_by_id.get(session_id)
                if not parent or parent == session_id:
                    return None
                return lineage_root_for(parent, seen) or parent

            items = []
            for record in records:
                session_id = stringify(record.get(context["session_id_column"]))
                if not session_id:
                    continue

                stats = message_stats.get(session_id, {})

                if context["session_message_count_column"] and record.get(context["session_message_count_column"]) is not None:
                    message_count = int(record.get(context["session_message_count_column"]))
                else:
                    message_count = stats.get("message_count", 0)

                last_active = stats.get("last_active")
                if last_active is None:
                    last_active = record.get(context["session_started_column"])

                preview = sqlite_preview_for_session(context, session_id) if include_previews else None

                title = None
                if context["session_title_column"]:
                    title = sanitize_title(record.get(context["session_title_column"]))
                if title is None and preview:
                    title = preview[:80]

                model = None
                if context["session_model_column"]:
                    model = sanitize_model(record.get(context["session_model_column"]))

                items.append({
                    "id": session_id,
                    "title": title,
                    "model": model,
                    "parent_session_id": normalize_json_value(record.get(context["session_parent_column"])),
                    "_lineage_root_id": normalize_json_value(lineage_root_for(session_id)),
                    "started_at": normalize_json_value(record.get(context["session_started_column"])),
                    "last_active": normalize_json_value(last_active),
                    "message_count": message_count,
                    "preview": preview,
                })

            items.sort(key=lambda item: sort_key(item.get("last_active") or item.get("started_at")), reverse=True)
            return items

        def discover_jsonl_artifacts():
            sessions_dir = resolved_hermes_home() / "sessions"
            if not sessions_dir.exists():
                return []

            return sorted(
                [item for item in sessions_dir.rglob("*.jsonl") if item.is_file()],
                key=lambda item: item.stat().st_mtime,
                reverse=True,
            )

        def discover_store_location(hinted_path=None, hinted_session_table=None, hinted_message_table=None):
            home = pathlib.Path.home()
            hermes_home = resolved_hermes_home()
            if not hermes_home.exists():
                return None, None, None

            for candidate in iter_session_store_candidates(hermes_home, home, hinted_path):
                try:
                    connection = connect_sqlite_readonly(candidate)
                    connection.execute("PRAGMA busy_timeout = 2000")
                    tables = [row[0] for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                    ).fetchall()]
                    session_table = None
                    message_table = None

                    if hinted_session_table:
                        for table in tables:
                            if table.lower() == hinted_session_table.lower():
                                session_table = table
                                break
                    if hinted_message_table:
                        for table in tables:
                            if table.lower() == hinted_message_table.lower():
                                message_table = table
                                break

                    if session_table is None:
                        session_table = choose_table(tables, "sessions")
                    if message_table is None:
                        message_table = choose_table(tables, "messages")

                    if session_table and message_table:
                        connection.close()
                        return str(candidate), session_table, message_table
                    connection.close()
                except Exception:
                    continue
            return None, None, None

        def try_open_store(hinted_path=None, hinted_session_table=None, hinted_message_table=None):
            store_path, session_table, message_table = discover_store_location(
                hinted_path,
                hinted_session_table,
                hinted_message_table
            )
            if not store_path:
                return None

            connection = connect_sqlite_readonly(store_path)
            connection.execute("PRAGMA busy_timeout = 2000")

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
            session_model_column = choose_column(session_columns, ["model"])
            session_parent_column = choose_column(session_columns, ["parent_session_id", "parent_id"])
            session_lineage_column = choose_column(session_columns, ["_lineage_root_id", "lineage_root_id", "lineage_root", "root_session_id"])

            message_id_column = choose_column(message_columns, ["id", "message_id"])
            message_session_id_column = choose_column(message_columns, ["session_id", "conversation_id"])
            message_role_column = choose_column(message_columns, ["role", "sender", "author"])
            message_content_column = choose_column(message_columns, ["content", "text", "body"])
            message_timestamp_column = choose_column(message_columns, ["timestamp", "created_at", "time"])
            message_search_columns = choose_columns(message_columns, [
                "content",
                "text",
                "body",
                "reasoning",
                "reasoning_content",
                "tool_calls",
            ])

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
                "store_path": store_path,
                "session_table": session_table,
                "message_table": message_table,
                "session_columns": session_columns,
                "message_columns": message_columns,
                "session_id_column": session_id_column,
                "session_title_column": session_title_column,
                "session_started_column": session_started_column,
                "session_message_count_column": session_message_count_column,
                "session_model_column": session_model_column,
                "session_parent_column": session_parent_column,
                "session_lineage_column": session_lineage_column,
                "message_id_column": message_id_column,
                "message_session_id_column": message_session_id_column,
                "message_role_column": message_role_column,
                "message_content_column": message_content_column,
                "message_timestamp_column": message_timestamp_column,
                "message_search_columns": message_search_columns,
            }

        def build_jsonl_session_summaries(search_query=None):
            items = []

            for path in discover_jsonl_artifacts():
                started_at = filename_timestamp(path) or path.stat().st_mtime
                last_active = started_at
                message_count = 0
                preview = None
                title = None
                model = None
                match_count = 0
                best_match = None

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
                            if role == "session_meta":
                                continue

                            if model is None:
                                model = extract_model_from_record(record)
                            timestamp = parse_timestamp_value(record.get("timestamp"))
                            if timestamp is not None:
                                if started_at is None:
                                    started_at = timestamp
                                last_active = timestamp

                            content = sanitize_preview(extract_record_content(record))
                            message_count += 1

                            if preview is None and content:
                                preview = content[:120]

                            if title is None and role in ("user", "assistant", "system") and content:
                                title = sanitize_title(content[:80])

                            if search_query is not None and value_matches_query(content, search_query):
                                match_count += 1
                                candidate_priority = role_priority(role)
                                if best_match is None or candidate_priority < best_match["_priority"]:
                                    best_match = {
                                        "match_count": 0,
                                        "message_id": str(message_count),
                                        "role": role,
                                        "timestamp": normalize_json_value(timestamp),
                                        "snippet": search_snippet(content, search_query),
                                        "_priority": candidate_priority,
                                    }
                except Exception:
                    continue

                item = {
                    "id": path.stem,
                    "title": title or path.stem,
                    "model": model,
                    "started_at": normalize_json_value(started_at),
                    "last_active": normalize_json_value(last_active or path.stat().st_mtime),
                    "message_count": message_count,
                    "preview": preview,
                }

                if best_match is not None:
                    best_match["match_count"] = match_count
                    best_match.pop("_priority", None)
                    item["search_match"] = best_match

                items.append(item)

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
                        normalized_value = prune_metadata_value(normalize_json_value(value))
                        if normalized_value is not None:
                            metadata[key] = normalized_value

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
    let query: String
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case offset
        case limit
        case query
        case hermesHome = "hermes_home"
    }
}

private struct SessionDetailRequest: Encodable {
    let sessionID: String
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hermesHome = "hermes_home"
    }
}

private struct SessionDeleteRequest: Encodable {
    let sessionID: String
    let hermesHome: String
    let hintedStorePath: String?
    let hintedSessionTable: String?
    let hintedMessageTable: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hermesHome = "hermes_home"
        case hintedStorePath = "hinted_store_path"
        case hintedSessionTable = "hinted_session_table"
        case hintedMessageTable = "hinted_message_table"
    }
}

private struct SessionDeleteResponse: Decodable {
    let ok: Bool
}
