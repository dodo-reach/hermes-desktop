import Foundation

final class MobileCompanionService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func gatewaySnapshot(connection: ConnectionProfile) async throws -> GatewaySnapshot {
        try await execute(connection: connection, operation: "gateway_snapshot")
    }

    func gatewayAction(_ action: GatewayLifecycleAction, connection: ConnectionProfile) async throws -> GatewaySnapshot {
        try await execute(connection: connection, operation: "gateway_action", arguments: ["action": action.rawValue])
    }

    func profileSnapshot(connection: ConnectionProfile) async throws -> ProfileManagementSnapshot {
        try await execute(connection: connection, operation: "profile_snapshot")
    }

    func deleteProfile(named name: String, confirmationFlag: String, connection: ConnectionProfile) async throws -> ProfileManagementSnapshot {
        try await execute(
            connection: connection,
            operation: "delete_profile",
            arguments: ["name": name, "confirmation_flag": confirmationFlag]
        )
    }

    func kanbanSnapshot(board: String?, connection: ConnectionProfile) async throws -> KanbanMobileSnapshot {
        try await execute(connection: connection, operation: "kanban_snapshot", arguments: ["board": board ?? "default"])
    }

    func updateKanbanTask(
        id: String,
        status: String?,
        assignee: String?,
        priority: Int?,
        comment: String?,
        board: String,
        connection: ConnectionProfile
    ) async throws -> KanbanMobileSnapshot {
        var arguments: [String: JSONValue] = [
            "task_id": .string(id),
            "board": .string(board),
        ]
        if let status { arguments["status"] = .string(status) }
        if let assignee { arguments["assignee"] = .string(assignee) }
        if let priority { arguments["priority"] = .number(Double(priority)) }
        if let comment { arguments["comment"] = .string(comment) }
        return try await execute(connection: connection, operation: "kanban_update", jsonArguments: arguments)
    }

    func configSnapshot(connection: ConnectionProfile) async throws -> ConfigSnapshot {
        try await execute(connection: connection, operation: "config_snapshot")
    }

    func saveConfig(fields: [ConfigField], expectedHash: String, connection: ConnectionProfile) async throws -> ConfigSnapshot {
        let data = try JSONEncoder().encode(fields)
        let object = try JSONSerialization.jsonObject(with: data)
        let values = (object as? [[String: Any]] ?? []).reduce(into: [String: JSONValue]()) { result, item in
            guard let path = item["path"] as? String, let rawValue = item["value"],
                  let valueData = try? JSONSerialization.data(withJSONObject: rawValue),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: valueData) else { return }
            result[path] = value
        }
        return try await execute(
            connection: connection,
            operation: "config_save",
            jsonArguments: ["expected_hash": .string(expectedHash), "values": .object(values)]
        )
    }

    func environmentSnapshot(connection: ConnectionProfile) async throws -> EnvironmentSnapshot {
        try await execute(connection: connection, operation: "env_snapshot")
    }

    func updateEnvironment(name: String, value: String?, clear: Bool, connection: ConnectionProfile) async throws -> EnvironmentSnapshot {
        var arguments: [String: JSONValue] = [
            "name": .string(name),
            "clear": .bool(clear),
        ]
        if let value { arguments["value"] = .string(value) }
        return try await execute(connection: connection, operation: "env_update", jsonArguments: arguments)
    }

    private func execute<Response: Decodable>(
        connection: ConnectionProfile,
        operation: String,
        arguments: [String: String] = [:],
        jsonArguments: [String: JSONValue]? = nil
    ) async throws -> Response {
        var values = jsonArguments ?? arguments.mapValues(JSONValue.string)
        values["operation"] = .string(operation)
        values["hermes_home"] = .string(connection.remoteHermesHomePath)
        if let profile = connection.cliHermesProfileName {
            values["profile_name"] = .string(profile)
        }
        let script = try RemotePythonScript.wrap(JSONValue.object(values), body: Self.remoteScript)
        return try await sshTransport.executeJSON(on: connection, pythonScript: script, responseType: Response.self)
    }

    static let remoteScript = #"""
import hashlib
import json
import os
import pathlib
import re
import shutil
import sqlite3
import subprocess
import tempfile

home = pathlib.Path.home()
requested_home = pathlib.Path(os.path.expanduser(str(payload.get("hermes_home") or "~/.hermes")))
profile_name = str(payload.get("profile_name") or "").strip()
hermes = shutil.which("hermes")

def command_args(*parts):
    args = [hermes]
    if profile_name and profile_name != "default":
        args += ["-p", profile_name]
    return args + list(parts)

def run(*parts, timeout=30):
    if not hermes:
        return subprocess.CompletedProcess([], 127, "", "Hermes CLI is not installed.")
    environment = os.environ.copy()
    environment["HERMES_HOME"] = str(requested_home)
    return subprocess.run(command_args(*parts), capture_output=True, text=True, timeout=timeout, env=environment)

def cleaned(text):
    return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text or "").strip()

def yaml_module():
    try:
        import yaml
        return yaml
    except Exception:
        return None

def read_yaml(path):
    module = yaml_module()
    if module is None or not path.exists():
        return {}
    value = module.safe_load(path.read_text(encoding="utf-8"))
    return value if isinstance(value, dict) else {}

def atomic_write(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        os.chmod(path, mode)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def gateway_snapshot():
    help_result = run("gateway", "--help")
    lifecycle = help_result.returncode == 0 and all(word in help_result.stdout for word in ("start", "stop", "restart", "status"))
    result = run("gateway", "status")
    output = cleaned((result.stdout or "") + "\n" + (result.stderr or ""))
    lower = output.lower()
    running = None
    if output:
        running = not any(token in lower for token in ("not running", "stopped", "inactive", "no gateway"))
        if any(token in lower for token in ("running", "active", "pid")):
            running = True
    manager = next((name for name in ("systemd", "launchd", "s6", "manual", "termux", "docker") if name in lower), None)
    config = read_yaml(requested_home / "config.yaml")
    channels = []
    channel_root = config.get("channels") if isinstance(config.get("channels"), dict) else {}
    candidates = set(channel_root.keys())
    candidates.update(key for key in config.keys() if str(key).lower() in {"telegram", "discord", "slack", "whatsapp", "signal", "matrix"})
    for raw_name in sorted(candidates, key=lambda value: str(value).lower()):
        name = str(raw_name)
        value = channel_root.get(raw_name, config.get(raw_name))
        mapping = value if isinstance(value, dict) else {}
        configured = bool(mapping) and any(v not in (None, "", False, [], {}) for k, v in mapping.items() if "token" not in str(k).lower() and "secret" not in str(k).lower())
        configured = configured or any("token" in str(k).lower() or "secret" in str(k).lower() for k in mapping)
        channels.append({"id": name.lower(), "name": name.replace("_", " ").title(), "enabled": mapping.get("enabled"), "configured": configured})
    error = output if result.returncode != 0 else None
    return {
        "profile_name": profile_name or "default",
        "cli_available": hermes is not None,
        "lifecycle_available": lifecycle,
        "running": running,
        "manager": manager,
        "service_status": output[:800] or None,
        "last_error": error[:800] if error else None,
        "channels": channels,
    }

def profile_snapshot():
    profiles = [{"name": "default", "path": "~/.hermes", "is_default": True, "exists": (home / ".hermes").exists()}]
    profiles_dir = home / ".hermes" / "profiles"
    if profiles_dir.exists():
        for path in sorted((item for item in profiles_dir.iterdir() if item.is_dir()), key=lambda item: item.name.lower()):
            profiles.append({"name": path.name, "path": "~/.hermes/profiles/" + path.name, "is_default": False, "exists": True})
    result = run("profile", "--help")
    if result.returncode != 0:
        result = run("profiles", "--help")
    text = cleaned((result.stdout or "") + "\n" + (result.stderr or ""))
    delete_available = "delete" in text or "remove" in text
    flag = next((candidate for candidate in ("--yes", "-y", "--force", "--no-input", "--non-interactive") if candidate in text), None)
    return {"profiles": profiles, "delete_command_available": delete_available, "noninteractive_delete_flag": flag}

def kanban_path(board):
    if board and board != "default":
        candidates = [
            home / ".hermes" / "kanban" / "boards" / board / "kanban.db",
            home / ".hermes" / "kanban" / f"{board}.db",
            home / ".hermes" / "kanban" / board / "kanban.db",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
    return home / ".hermes" / "kanban.db"

def kanban_snapshot():
    board = str(payload.get("board") or "default")
    path = kanban_path(board)
    boards = [{"slug": "default", "name": "Default"}]
    board_root = home / ".hermes" / "kanban" / "boards"
    if board_root.exists():
        for item in sorted((entry for entry in board_root.iterdir() if entry.is_dir()), key=lambda entry: entry.name.lower()):
            if (item / "kanban.db").exists() or (item / "board.json").exists():
                name = item.name.replace("-", " ").replace("_", " ").title()
                metadata = item / "board.json"
                if metadata.exists():
                    try:
                        raw_metadata = json.loads(metadata.read_text(encoding="utf-8"))
                        name = str(raw_metadata.get("name") or name)
                    except Exception:
                        pass
                boards.append({"slug": item.name, "name": name})
    if not path.exists():
        return {"available": False, "database_path": str(path), "board_slug": board, "boards": boards, "tasks": [], "latest_event_id": None, "warning": "Kanban is not initialized on this host."}
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    tables = {row[0] for row in connection.execute("select name from sqlite_master where type='table'")}
    task_table = next((name for name in ("tasks", "kanban_tasks") if name in tables), None)
    if not task_table:
        connection.close()
        return {"available": False, "database_path": str(path), "board_slug": board, "boards": boards, "tasks": [], "latest_event_id": None, "warning": "Unsupported Kanban database schema."}
    columns = {row[1] for row in connection.execute(f"pragma table_info({task_table})")}
    if "updated_at" in columns:
        order_clause = "updated_at DESC"
    elif "created_at" in columns:
        order_clause = "created_at DESC"
    elif "priority" in columns:
        order_clause = "priority DESC"
    else:
        order_clause = "rowid DESC"
    rows = connection.execute(f"select * from {task_table} order by {order_clause}").fetchall()
    comments_by_task = {}
    comment_table = next((name for name in ("task_comments", "comments") if name in tables), None)
    if comment_table:
        comment_columns = {row[1] for row in connection.execute(f"pragma table_info({comment_table})")}
        comment_order = "created_at ASC, id ASC" if "created_at" in comment_columns else "id ASC"
        for row in connection.execute(f"select * from {comment_table} order by {comment_order}"):
            record = dict(row)
            task_id = str(record.get("task_id") or "")
            comments_by_task.setdefault(task_id, []).append({"id": str(record.get("id") or len(comments_by_task.get(task_id, []))), "author": record.get("author"), "body": str(record.get("body") or record.get("content") or ""), "created_at": record.get("created_at")})
    latest = None
    event_table = next((name for name in ("task_events", "events") if name in tables), None)
    if event_table:
        latest = connection.execute(f"select max(id) from {event_table}").fetchone()[0]
    tasks = []
    for row in rows:
        record = dict(row)
        task_id = str(record.get("id"))
        comments = comments_by_task.get(task_id, [])
        tasks.append({"id": task_id, "title": str(record.get("title") or task_id), "body": record.get("body") or record.get("description"), "status": str(record.get("status") or "unknown"), "assignee": record.get("assignee"), "priority": int(record.get("priority") or 0), "comment_count": len(comments), "comments": comments})
    connection.close()
    return {"available": True, "database_path": str(path), "board_slug": board, "boards": boards, "tasks": tasks, "latest_event_id": latest, "warning": None}

def kanban_update():
    board = str(payload.get("board") or "default")
    task_id = str(payload.get("task_id") or "")
    if not task_id:
        raise RuntimeError("The Kanban task ID is required.")
    prefix = ["kanban"]
    if board != "default":
        prefix += ["--board", board]
    help_result = run("kanban", "--help")
    help_text = cleaned((help_result.stdout or "") + "\n" + (help_result.stderr or ""))
    commands = []
    if payload.get("comment") is not None:
        if "comment" not in help_text:
            raise RuntimeError("This Hermes CLI does not expose Kanban comments.")
        commands.append(prefix + ["comment", "--author", profile_name or "HermesPhone", task_id, str(payload.get("comment"))])
    if payload.get("assignee") is not None:
        if "assign" not in help_text:
            raise RuntimeError("This Hermes CLI does not expose Kanban assignment.")
        commands.append(prefix + ["assign", task_id, str(payload.get("assignee") or "none")])
    status = payload.get("status")
    if status is not None:
        status = str(status)
        current = next((item for item in kanban_snapshot()["tasks"] if item["id"] == task_id), None)
        current_status = current["status"] if current else None
        if status == "blocked":
            commands.append(prefix + ["block", task_id])
        elif status == "done":
            commands.append(prefix + ["complete", task_id])
        elif current_status == "blocked" and status in {"ready", "todo"}:
            commands.append(prefix + ["unblock", task_id])
        else:
            raise RuntimeError("This status transition is not exposed safely by the installed Hermes CLI.")
    for parts in commands:
        result = run(*parts, timeout=60)
        if result.returncode != 0:
            raise RuntimeError(cleaned(result.stderr or result.stdout) or "Kanban update failed.")
    return kanban_snapshot()

FALLBACK_SCHEMA_OVERRIDES = {
    "model": {"type": "string", "description": "Default model used for new sessions.", "category": "general"},
    "model_context_length": {"type": "number", "description": "Context window override. Leave 0 to detect it from the model.", "category": "general"},
    "terminal.backend": {"type": "select", "description": "Where Hermes runs terminal commands.", "options": ["local", "docker", "ssh", "modal", "daytona", "singularity"]},
    "approvals.mode": {"type": "select", "description": "How Hermes handles commands that need approval.", "options": ["ask", "yolo", "deny"]},
    "memory.provider": {"type": "select", "description": "Persistent memory provider.", "options": ["builtin", "honcho"]},
    "delegation.reasoning_effort": {"type": "select", "description": "Reasoning effort used by delegated subagents.", "options": ["", "low", "medium", "high"]},
    "display.resume_display": {"type": "select", "description": "How much history appears when a session resumes.", "options": ["minimal", "full", "off"]},
    "display.busy_input_mode": {"type": "select", "description": "What new messages do while Hermes is already working.", "options": ["interrupt", "queue", "steer"]},
}

FALLBACK_CATEGORY_MERGE = {
    "privacy": "security",
    "context": "agent",
    "skills": "agent",
    "cron": "agent",
    "network": "agent",
    "checkpoints": "agent",
    "approvals": "security",
    "human_delay": "display",
    "dashboard": "display",
    "code_execution": "agent",
    "prompt_caching": "agent",
    "goals": "agent",
    "updates": "general",
    "onboarding": "agent",
    "telegram": "discord",
}

FALLBACK_CATEGORY_ORDER = [
    "general", "agent", "terminal", "display", "delegation",
    "memory", "compression", "security", "browser", "voice",
    "tts", "stt", "logging", "discord", "auxiliary",
]

def installed_schema():
    try:
        from hermes_cli.web_server import CONFIG_SCHEMA, _CATEGORY_ORDER
        if isinstance(CONFIG_SCHEMA, dict):
            return CONFIG_SCHEMA, list(_CATEGORY_ORDER)
    except Exception:
        pass
    return {}, FALLBACK_CATEGORY_ORDER

def fallback_schema_entry(path, value):
    kind = "object" if isinstance(value, dict) else "list" if isinstance(value, list) else "boolean" if isinstance(value, bool) else "number" if isinstance(value, (int, float)) else "string"
    category = path.split(".", 1)[0] if "." in path else "general"
    entry = {
        "type": kind,
        "description": path.replace(".", " → ").replace("_", " ").title(),
        "category": FALLBACK_CATEGORY_MERGE.get(category, category),
    }
    entry.update(FALLBACK_SCHEMA_OVERRIDES.get(path, {}))
    entry["category"] = FALLBACK_CATEGORY_MERGE.get(entry.get("category"), entry.get("category"))
    return entry

def flatten(mapping, defaults, schema, prefix=""):
    fields = []
    keys = sorted(set(mapping.keys()) | set(defaults.keys()))
    for key in keys:
        path = f"{prefix}.{key}" if prefix else str(key)
        if path == "_config_version":
            continue
        value = mapping.get(key, defaults.get(key))
        default = defaults.get(key)
        if isinstance(value, dict) and isinstance(default, dict):
            fields += flatten(value, default, schema, path)
            continue
        metadata = schema.get(path) if isinstance(schema.get(path), dict) else fallback_schema_entry(path, value)
        raw_kind = str(metadata.get("type") or "")
        kind = "bool" if raw_kind in {"bool", "boolean"} else "string" if raw_kind == "select" else raw_kind or fallback_schema_entry(path, value)["type"]
        fields.append({
            "path": path,
            "title": str(key).replace("_", " ").title(),
            "category": str(metadata.get("category") or "general").lower(),
            "description": metadata.get("description"),
            "kind": kind,
            "enum_values": list(metadata.get("options") or []),
            "value": value,
            "default_value": default,
        })
    return fields

def installed_defaults():
    for module_name in ("hermes_constants", "hermes_cli.config"):
        try:
            module = __import__(module_name, fromlist=["DEFAULT_CONFIG"])
            value = getattr(module, "DEFAULT_CONFIG", None)
            if isinstance(value, dict):
                return value
        except Exception:
            pass
    return {}

def config_snapshot():
    path = requested_home / "config.yaml"
    raw = path.read_bytes() if path.exists() else b""
    current = read_yaml(path)
    defaults = installed_defaults()
    schema, category_order = installed_schema()
    return {
        "content_hash": hashlib.sha256(raw).hexdigest(),
        "fields": flatten(current, defaults, schema),
        "category_order": category_order,
        "unknown_json": json.dumps(current, ensure_ascii=False),
        "validation_available": hermes is not None and any(word in cleaned(run("config", "--help").stdout) for word in ("check", "validate")),
    }

def set_nested(mapping, path, value):
    parts = path.split(".")
    target = mapping
    for part in parts[:-1]:
        if not isinstance(target.get(part), dict):
            target[part] = {}
        target = target[part]
    target[parts[-1]] = value

def save_config():
    path = requested_home / "config.yaml"
    raw = path.read_bytes() if path.exists() else b""
    existed = path.exists()
    if hashlib.sha256(raw).hexdigest() != str(payload.get("expected_hash") or ""):
        raise RuntimeError("config.yaml changed on the host. Reload before saving.")
    current = read_yaml(path)
    for key, value in (payload.get("values") or {}).items():
        set_nested(current, key, value)
    module = yaml_module()
    if module is None:
        raise RuntimeError("PyYAML is required on the host to edit config.yaml safely.")
    atomic_write(path, module.safe_dump(current, sort_keys=False, allow_unicode=True), 0o600)
    config_help = cleaned(run("config", "--help").stdout)
    if "check" in config_help:
        validation = run("config", "check", timeout=60)
        if validation.returncode != 0:
            if existed:
                atomic_write(path, raw.decode("utf-8"), 0o600)
            elif path.exists():
                path.unlink()
            raise RuntimeError(cleaned(validation.stderr or validation.stdout) or "Hermes rejected the updated configuration.")
    return config_snapshot()

FALLBACK_ENV = {
    "OPENAI_API_KEY": {"category": "provider", "description": "OpenAI API key", "password": True},
    "ANTHROPIC_API_KEY": {"category": "provider", "description": "Anthropic API key", "password": True},
    "OPENROUTER_API_KEY": {"category": "provider", "description": "OpenRouter API key", "password": True},
    "TELEGRAM_BOT_TOKEN": {"category": "messaging", "description": "Telegram bot token", "password": True},
    "DISCORD_BOT_TOKEN": {"category": "messaging", "description": "Discord bot token", "password": True},
    "SLACK_BOT_TOKEN": {"category": "messaging", "description": "Slack bot token", "password": True},
    "SLACK_APP_TOKEN": {"category": "messaging", "description": "Slack app token", "password": True},
}

def installed_env_catalog():
    try:
        from hermes_cli.config import OPTIONAL_ENV_VARS
        if isinstance(OPTIONAL_ENV_VARS, dict):
            return OPTIONAL_ENV_VARS
    except Exception:
        pass
    return FALLBACK_ENV

def env_lines():
    path = requested_home / ".env"
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    names = set()
    for line in lines:
        match = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
        if match:
            names.add(match.group(1))
    return path, lines, names

def env_snapshot():
    _, _, existing = env_lines()
    catalog = installed_env_catalog()
    names = sorted(existing | set(catalog))
    variables = []
    for name in names:
        info = catalog.get(name) if isinstance(catalog.get(name), dict) else {}
        variables.append({
            "name": name,
            "category": str(info.get("category") or "other").lower(),
            "description": info.get("description"),
            "is_set": name in existing,
            "url": info.get("url"),
            "tools": list(info.get("tools") or []),
            "advanced": bool(info.get("advanced", False)),
            "is_password": bool(info.get("password", True)),
        })
    return {"variables": variables}

def env_update():
    path, lines, _ = env_lines()
    name = str(payload.get("name") or "")
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
        raise RuntimeError("Invalid environment variable name.")
    clear = bool(payload.get("clear"))
    value = payload.get("value")
    pattern = re.compile(r"^\s*(?:export\s+)?" + re.escape(name) + r"\s*=")
    output = [line for line in lines if not pattern.match(line)]
    if not clear:
        if value is None or value == "":
            return env_snapshot()
        escaped = str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
        output.append(f'{name}="{escaped}"')
    atomic_write(path, "\n".join(output).rstrip() + ("\n" if output else ""), 0o600)
    return env_snapshot()

operation = str(payload.get("operation") or "")
try:
    if operation == "gateway_snapshot":
        result = gateway_snapshot()
    elif operation == "gateway_action":
        action = str(payload.get("action") or "")
        if action not in {"start", "stop", "restart"}:
            raise RuntimeError("Unsupported gateway action.")
        before = gateway_snapshot()
        if not before["lifecycle_available"]:
            raise RuntimeError("This Hermes CLI does not expose unambiguous gateway lifecycle commands.")
        action_result = run("gateway", action, timeout=90)
        if action_result.returncode != 0:
            raise RuntimeError(cleaned(action_result.stderr or action_result.stdout) or f"Gateway {action} failed.")
        result = gateway_snapshot()
    elif operation == "profile_snapshot":
        result = profile_snapshot()
    elif operation == "delete_profile":
        name = str(payload.get("name") or "")
        flag = str(payload.get("confirmation_flag") or "")
        snapshot = profile_snapshot()
        if name in ("", "default", profile_name):
            raise RuntimeError("The default or currently active profile cannot be deleted.")
        if flag != snapshot.get("noninteractive_delete_flag"):
            raise RuntimeError("The installed Hermes CLI did not expose a verified noninteractive delete flag.")
        command = "delete" if "delete" in cleaned(run("profile", "--help").stdout) else "remove"
        deletion = run("profile", command, name, flag, timeout=90)
        if deletion.returncode != 0:
            deletion = run("profiles", command, name, flag, timeout=90)
        if deletion.returncode != 0:
            raise RuntimeError(cleaned(deletion.stderr or deletion.stdout) or "Profile deletion failed.")
        result = profile_snapshot()
    elif operation == "kanban_snapshot":
        result = kanban_snapshot()
    elif operation == "kanban_update":
        result = kanban_update()
    elif operation == "config_snapshot":
        result = config_snapshot()
    elif operation == "config_save":
        result = save_config()
    elif operation == "env_snapshot":
        result = env_snapshot()
    elif operation == "env_update":
        result = env_update()
    else:
        raise RuntimeError("Unsupported mobile companion operation.")
    result["ok"] = True
    print(json.dumps(result, ensure_ascii=False))
except Exception as exc:
    fail(str(exc))
"""#
}
