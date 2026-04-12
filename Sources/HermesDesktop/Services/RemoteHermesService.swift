import Foundation

final class RemoteHermesService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func discover(connection: ConnectionProfile, hermesHome: String = "~/.hermes") async throws -> RemoteDiscovery {
        let script = try RemotePythonScript.wrap(
            HermesDiscoveryRequest(hermesHome: hermesHome),
            body: discoveryBody
        )
        return try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: RemoteDiscovery.self
        )
    }

    func discoverProfiles(connection: ConnectionProfile) async throws -> [HermesAgentProfile] {
        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: profilesScript,
            responseType: ProfilesResponse.self
        )
        return response.profiles
    }

    private var discoveryBody: String {
        """
        import json
        import pathlib
        import sqlite3
        import sys

        def tilde(path: pathlib.Path, home: pathlib.Path) -> str:
            try:
                relative = path.relative_to(home)
                return "~/" + relative.as_posix() if relative.as_posix() != "." else "~"
            except ValueError:
                return path.as_posix()

        def choose_table(tables, needle):
            lowered = needle.lower()
            for table in tables:
                if table.lower() == lowered:
                    return table
            for table in tables:
                if lowered in table.lower():
                    return table
            return None

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def iter_session_store_candidates(hermes_home: pathlib.Path):
            seen = set()

            def emit(candidate: pathlib.Path):
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

        def discover_session_store(hermes_home: pathlib.Path):
            if not hermes_home.exists():
                return None

            for candidate in iter_session_store_candidates(hermes_home):
                try:
                    conn = sqlite3.connect(f"file:{candidate}?mode=ro", uri=True)
                    cursor = conn.execute(
                        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                    )
                    tables = [row[0] for row in cursor.fetchall()]
                    session_table = choose_table(tables, "sessions")
                    message_table = choose_table(tables, "messages")
                    if session_table and message_table:
                        conn.close()
                        return {
                            "kind": "sqlite",
                            "path": tilde(candidate, home),
                            "session_table": session_table,
                            "message_table": message_table,
                        }
                    conn.close()
                except Exception:
                    continue

            return None

        try:
            home = pathlib.Path.home()
            hermes_home = pathlib.Path(payload["hermes_home"]).expanduser()
            user_path = hermes_home / "memories" / "USER.md"
            memory_path = hermes_home / "memories" / "MEMORY.md"
            soul_path = hermes_home / "SOUL.md"
            sessions_dir = hermes_home / "sessions"

            result = {
                "ok": True,
                "remote_home": tilde(home, home),
                "hermes_home": tilde(hermes_home, home),
                "paths": {
                    "user": tilde(user_path, home),
                    "memory": tilde(memory_path, home),
                    "soul": tilde(soul_path, home),
                    "sessions_dir": tilde(sessions_dir, home),
                },
                "exists": {
                    "user": user_path.exists(),
                    "memory": memory_path.exists(),
                    "soul": soul_path.exists(),
                    "sessions_dir": sessions_dir.exists(),
                },
                "session_store": discover_session_store(hermes_home),
            }

            print(json.dumps(result, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to discover the remote Hermes workspace: {exc}")
        """
    }

    private var profilesScript: String {
        """
        import json
        import pathlib

        home = pathlib.Path.home()
        hermes_root = home / ".hermes"
        profiles_dir = hermes_root / "profiles"

        profiles = [{"id": "", "hermesHome": str(hermes_root)}]

        if profiles_dir.exists() and profiles_dir.is_dir():
            for entry in sorted(profiles_dir.iterdir()):
                if entry.is_dir():
                    profiles.append({"id": entry.name, "hermesHome": str(entry)})

        print(json.dumps({"profiles": profiles}, ensure_ascii=False))
        """
    }
}

private struct HermesDiscoveryRequest: Encodable {
    let hermesHome: String
    enum CodingKeys: String, CodingKey {
        case hermesHome = "hermes_home"
    }
}

private struct ProfilesResponse: Decodable {
    let profiles: [HermesAgentProfile]
}
