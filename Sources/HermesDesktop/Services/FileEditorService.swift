import Foundation

final class FileEditorService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func read(
        file: RemoteTrackedFile,
        remotePath: String,
        connection: ConnectionProfile
    ) async throws -> FileSnapshot {
        let script = try RemotePythonScript.wrap(
            FileRequest(path: remotePath),
            body: """
            import hashlib
            import json
            import os
            import pathlib
            import sys

            def fail(message):
                print(json.dumps({
                    "ok": False,
                    "error": message,
                }, ensure_ascii=False))
                sys.exit(1)

            try:
                target = pathlib.Path(os.path.expanduser(payload["path"]))
                if not target.exists():
                    fail(f"{payload['path']} does not exist on the active host.")
                if not target.is_file():
                    fail(f"{payload['path']} is not a regular file.")

                raw_content = target.read_bytes()
                content_hash = hashlib.sha256(raw_content).hexdigest()
                content = raw_content.decode("utf-8")
                print(json.dumps({
                    "ok": True,
                    "content": content,
                    "content_hash": content_hash,
                }, ensure_ascii=False))
            except UnicodeDecodeError:
                fail(f"{payload['path']} is not valid UTF-8.")
            except PermissionError:
                fail(f"Permission denied while reading {payload['path']}.")
            except Exception as exc:
                fail(f"Unable to read {payload['path']}: {exc}")
            """
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: FileReadResponse.self
        )

        return FileSnapshot(
            content: response.content,
            contentHash: response.contentHash
        )
    }

    func write(
        file: RemoteTrackedFile,
        remotePath: String,
        content: String,
        expectedContentHash: String?,
        connection: ConnectionProfile
    ) async throws -> FileSaveResult {
        let script = try RemotePythonScript.wrap(
            FileWriteRequest(
                path: remotePath,
                content: content,
                expectedContentHash: expectedContentHash,
                atomic: true
            ),
            body: """
            import hashlib
            import json
            import os
            import pathlib
            import sys
            import tempfile

            def fail(message):
                print(json.dumps({
                    "ok": False,
                    "error": message,
                }, ensure_ascii=False))
                sys.exit(1)

            temp_name = None
            directory_fd = None
            content_bytes = payload["content"].encode("utf-8")
            expected_hash = payload.get("expected_content_hash")

            try:
                target = pathlib.Path(os.path.expanduser(payload["path"]))
                target.parent.mkdir(parents=True, exist_ok=True)

                if expected_hash is not None:
                    if not target.exists():
                        fail(f"{payload['path']} was removed on the active host after it was loaded. Reload from Remote before saving.")
                    if not target.is_file():
                        fail(f"{payload['path']} is not a regular file anymore. Reload from Remote before saving.")

                    current_bytes = target.read_bytes()
                    current_hash = hashlib.sha256(current_bytes).hexdigest()
                    if current_hash != expected_hash:
                        fail(f"{payload['path']} changed on the active host after it was loaded. Reload from Remote before saving.")

                fd, temp_name = tempfile.mkstemp(
                    dir=str(target.parent),
                    prefix=f".{target.name}.",
                    suffix=".tmp",
                )

                with os.fdopen(fd, "wb") as handle:
                    handle.write(content_bytes)
                    handle.flush()
                    os.fsync(handle.fileno())

                if target.exists():
                    os.chmod(temp_name, target.stat().st_mode)

                os.replace(temp_name, target)

                directory_fd = os.open(target.parent, os.O_RDONLY)
                os.fsync(directory_fd)

                print(json.dumps({
                    "ok": True,
                    "path": payload["path"],
                    "content_hash": hashlib.sha256(content_bytes).hexdigest(),
                }, ensure_ascii=False))
            except PermissionError:
                fail(f"Permission denied while writing {payload['path']}.")
            except Exception as exc:
                fail(f"Unable to write {payload['path']}: {exc}")
            finally:
                if directory_fd is not None:
                    os.close(directory_fd)
                if temp_name and os.path.exists(temp_name):
                    os.unlink(temp_name)
            """
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: FileWriteResponse.self
        )

        return FileSaveResult(
            path: response.path,
            contentHash: response.contentHash
        )
    }
}

private struct FileRequest: Encodable {
    let path: String
}

private struct FileWriteRequest: Encodable {
    let path: String
    let content: String
    let expectedContentHash: String?
    let atomic: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case content
        case expectedContentHash = "expected_content_hash"
        case atomic
    }
}

private struct FileReadResponse: Decodable {
    let ok: Bool
    let content: String
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case ok
        case content
        case contentHash = "content_hash"
    }
}

private struct FileWriteResponse: Decodable {
    let ok: Bool
    let path: String
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case ok
        case path
        case contentHash = "content_hash"
    }
}

struct FileSnapshot {
    let content: String
    let contentHash: String
}

struct FileSaveResult {
    let path: String
    let contentHash: String
}
