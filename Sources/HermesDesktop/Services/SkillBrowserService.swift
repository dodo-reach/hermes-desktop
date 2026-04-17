import Foundation

final class SkillBrowserService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func listSkills(connection: ConnectionProfile) async throws -> [SkillSummary] {
        let script = try RemotePythonScript.wrap(
            EmptySkillRequest(hermesHome: connection.remoteHermesHomePath),
            body: skillListBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SkillListResponse.self
        )

        return response.items
    }

    func loadSkillDetail(
        connection: ConnectionProfile,
        relativePath: String
    ) async throws -> SkillDetail {
        let script = try RemotePythonScript.wrap(
            SkillDetailRequest(
                relativePath: relativePath,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: skillDetailBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SkillDetailResponse.self
        )

        return response.item
    }

    func createSkill(
        connection: ConnectionProfile,
        draft: SkillDraft
    ) async throws -> SkillDetail {
        let script = try RemotePythonScript.wrap(
            SkillWriteRequest(
                relativePath: draft.relativePath,
                markdownContent: draft.generatedMarkdown,
                expectedContentHash: nil,
                createReferencesFolder: draft.includeReferencesFolder,
                createScriptsFolder: draft.includeScriptsFolder,
                createTemplatesFolder: draft.includeTemplatesFolder,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: skillWriteBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SkillWriteResponse.self
        )

        return response.item
    }

    func updateSkill(
        connection: ConnectionProfile,
        relativePath: String,
        markdownContent: String,
        expectedContentHash: String,
        ensureReferencesFolder: Bool,
        ensureScriptsFolder: Bool,
        ensureTemplatesFolder: Bool
    ) async throws -> SkillDetail {
        let script = try RemotePythonScript.wrap(
            SkillWriteRequest(
                relativePath: relativePath,
                markdownContent: markdownContent,
                expectedContentHash: expectedContentHash,
                createReferencesFolder: ensureReferencesFolder,
                createScriptsFolder: ensureScriptsFolder,
                createTemplatesFolder: ensureTemplatesFolder,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: skillWriteBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SkillWriteResponse.self
        )

        return response.item
    }

    private var skillListBody: String {
        sharedSkillHelpers + """

        try:
            items = discover_skill_items()
            print(json.dumps({
                "ok": True,
                "items": items,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to read the remote Hermes skill library: {exc}")
        """
    }

    private var skillDetailBody: String {
        sharedSkillHelpers + """

        try:
            item = build_skill_detail(payload["relative_path"])
            print(json.dumps({
                "ok": True,
                "item": item,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to read the remote Hermes skill detail: {exc}")
        """
    }

    private var skillWriteBody: String {
        sharedSkillHelpers + """

        import hashlib
        import os
        import tempfile

        def write_atomic_utf8(target, content):
            temp_name = None
            directory_fd = None
            content_bytes = content.encode("utf-8")

            try:
                target.parent.mkdir(parents=True, exist_ok=True)

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
            finally:
                if directory_fd is not None:
                    os.close(directory_fd)
                if temp_name and os.path.exists(temp_name):
                    os.unlink(temp_name)

            return hashlib.sha256(content_bytes).hexdigest()

        try:
            relative_path = normalize_text(payload.get("relative_path"))
            if relative_path is None:
                fail("The skill path is required.")

            markdown_content = payload.get("markdown_content")
            if not isinstance(markdown_content, str) or not markdown_content.strip():
                fail("SKILL.md content is required.")

            root = skills_root()
            root.mkdir(parents=True, exist_ok=True)

            skill_file, _ = resolve_skill_file(relative_path)
            skill_dir = skill_file.parent
            expected_hash = normalize_text(payload.get("expected_content_hash"))

            if expected_hash is None:
                if skill_file.exists():
                    fail(f"A skill already exists at {relative_path}.")
            else:
                if not skill_file.exists():
                    fail(f"{relative_path} no longer exists. Reload the skill list and try again.")
                if not skill_file.is_file():
                    fail(f"{relative_path} does not resolve to a writable SKILL.md file.")

                current_hash = hashlib.sha256(skill_file.read_bytes()).hexdigest()
                if current_hash != expected_hash:
                    fail(f"{relative_path} changed on the active host after it was loaded. Reload the skill before saving.")

            if payload.get("create_references_folder"):
                (skill_dir / "references").mkdir(parents=True, exist_ok=True)
            if payload.get("create_scripts_folder"):
                (skill_dir / "scripts").mkdir(parents=True, exist_ok=True)
            if payload.get("create_templates_folder"):
                (skill_dir / "templates").mkdir(parents=True, exist_ok=True)

            write_atomic_utf8(skill_file, markdown_content)
            item = build_skill_detail(relative_path)

            print(json.dumps({
                "ok": True,
                "item": item,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to save the remote Hermes skill: {exc}")
        """
    }

    private var sharedSkillHelpers: String {
        """
        import ast
        import hashlib
        import json
        import os
        import pathlib
        import re
        import sys

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def skills_root():
            requested = payload.get("hermes_home")
            home = pathlib.Path.home()

            if requested == "~":
                hermes_home = home
            elif isinstance(requested, str) and requested.startswith("~/"):
                hermes_home = home / requested[2:]
            elif requested:
                hermes_home = pathlib.Path(requested)
            else:
                hermes_home = home / ".hermes"

            return hermes_home / "skills"

        def normalize_text(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                value = value.decode("utf-8", errors="replace")
            value = str(value).strip()
            return value or None

        def normalize_text_list(value):
            if value is None:
                return []
            if isinstance(value, (list, tuple, set)):
                result = []
                for item in value:
                    normalized = normalize_text(item)
                    if normalized is not None:
                        result.append(normalized)
                return result

            normalized = normalize_text(value)
            return [normalized] if normalized is not None else []

        def compact_text(value):
            normalized = normalize_text(value)
            if normalized is None:
                return None
            return re.sub(r"\\s+", " ", normalized)

        def extract_frontmatter(content):
            lines = content.splitlines()
            if not lines or lines[0].strip() != "---":
                return None

            for index in range(1, len(lines)):
                if lines[index].strip() == "---":
                    return "\\n".join(lines[1:index])
            return None

        def indentation(line):
            return len(line) - len(line.lstrip(" "))

        def collect_child_block(lines, start, parent_indent):
            child_indent = parent_indent + 2
            collected = []
            index = start

            while index < len(lines):
                raw_line = lines[index]
                stripped = raw_line.strip()

                if not stripped:
                    collected.append("")
                    index += 1
                    continue

                current_indent = indentation(raw_line)
                if current_indent <= parent_indent:
                    break

                if current_indent >= child_indent:
                    collected.append(raw_line[child_indent:])
                else:
                    collected.append(raw_line.lstrip())
                index += 1

            return collected, index

        def collect_multiline_text(lines, start, parent_indent, folded):
            block_lines, index = collect_child_block(lines, start, parent_indent)
            if not block_lines:
                return None, index

            cleaned = [line.rstrip() for line in block_lines]
            if folded:
                text = " ".join(part for part in cleaned if part.strip())
            else:
                text = "\\n".join(cleaned).strip("\\n")
            return normalize_text(text), index

        def parse_inline_list(value):
            stripped = value.strip()
            if not (stripped.startswith("[") and stripped.endswith("]")):
                return None

            try:
                parsed = ast.literal_eval(stripped)
                if isinstance(parsed, list):
                    return normalize_text_list(parsed)
            except Exception:
                pass

            inner = stripped[1:-1].strip()
            if not inner:
                return []

            return [
                item.strip().strip("'\\\"")
                for item in inner.split(",")
                if item.strip()
            ]

        def parse_inline_scalar(value):
            stripped = value.strip()
            if not stripped or stripped in {"null", "Null", "NULL", "~"}:
                return None

            if (stripped.startswith("'") and stripped.endswith("'")) or (
                stripped.startswith("\"") and stripped.endswith("\"")
            ):
                try:
                    return normalize_text(ast.literal_eval(stripped))
                except Exception:
                    return normalize_text(stripped[1:-1])

            return normalize_text(stripped)

        def parse_block_list(block_lines):
            items = []
            for raw_line in block_lines:
                stripped = raw_line.strip()
                if not stripped:
                    continue
                if not stripped.startswith("- "):
                    return None
                items.append(parse_inline_scalar(stripped[2:]))
            return [item for item in items if item is not None]

        def parse_key_value(lines, key):
            index = 0

            while index < len(lines):
                raw_line = lines[index]
                stripped = raw_line.strip()

                if not stripped or stripped.startswith("#") or indentation(raw_line) != 0:
                    index += 1
                    continue

                if not stripped.startswith(f"{key}:"):
                    index += 1
                    continue

                value = stripped[len(key) + 1:].strip()
                if value == "|":
                    return collect_multiline_text(lines, index + 1, 0, folded=False)[0]
                if value == ">":
                    return collect_multiline_text(lines, index + 1, 0, folded=True)[0]

                inline_list = parse_inline_list(value)
                if inline_list is not None:
                    return inline_list

                if value:
                    return parse_inline_scalar(value)

                block_lines, _ = collect_child_block(lines, index + 1, 0)
                if not block_lines:
                    return None

                list_value = parse_block_list(block_lines)
                if list_value is not None:
                    return list_value

                text = "\\n".join(line.rstrip() for line in block_lines if line.strip())
                return normalize_text(text)

            return None

        def fallback_frontmatter_dict(frontmatter_text):
            lines = frontmatter_text.splitlines()
            metadata = {}

            metadata_block = parse_key_value(lines, "metadata")
            if isinstance(metadata_block, str):
                metadata_lines = metadata_block.splitlines()
            else:
                metadata_lines = []

            if not metadata_lines:
                index = 0
                while index < len(lines):
                    raw_line = lines[index]
                    stripped = raw_line.strip()
                    if indentation(raw_line) == 0 and stripped.startswith("metadata:"):
                        metadata_lines, _ = collect_child_block(lines, index + 1, 0)
                        break
                    index += 1

            if metadata_lines:
                tags = parse_key_value(metadata_lines, "tags")
                related_skills = parse_key_value(metadata_lines, "related_skills")

                hermes_lines = []
                index = 0
                while index < len(metadata_lines):
                    raw_line = metadata_lines[index]
                    stripped = raw_line.strip()
                    if indentation(raw_line) == 0 and stripped.startswith("hermes:"):
                        hermes_lines, _ = collect_child_block(metadata_lines, index + 1, 0)
                        break
                    index += 1

                if tags is None and hermes_lines:
                    tags = parse_key_value(hermes_lines, "tags")
                if related_skills is None and hermes_lines:
                    related_skills = parse_key_value(hermes_lines, "related_skills")

                if tags is not None:
                    metadata["tags"] = tags
                if related_skills is not None:
                    metadata["related_skills"] = related_skills

            result = {}
            for key in ("name", "description", "version"):
                value = parse_key_value(lines, key)
                if value is not None and not isinstance(value, list):
                    result[key] = value

            if metadata:
                result["metadata"] = metadata

            return result

        def parse_frontmatter(content):
            frontmatter_text = extract_frontmatter(content)
            if frontmatter_text is None:
                return {}

            data = None

            try:
                import yaml
                loaded = yaml.safe_load(frontmatter_text)
                if isinstance(loaded, dict):
                    data = loaded
            except Exception:
                data = None

            if not isinstance(data, dict):
                data = fallback_frontmatter_dict(frontmatter_text)

            metadata = data.get("metadata")
            if not isinstance(metadata, dict):
                metadata = {}

            hermes_metadata = metadata.get("hermes")
            if not isinstance(hermes_metadata, dict):
                hermes_metadata = {}

            tags = metadata.get("tags")
            if tags is None:
                tags = hermes_metadata.get("tags")

            related_skills = metadata.get("related_skills")
            if related_skills is None:
                related_skills = hermes_metadata.get("related_skills")

            return {
                "name": normalize_text(data.get("name")),
                "description": compact_text(data.get("description")),
                "version": normalize_text(data.get("version")),
                "tags": normalize_text_list(tags),
                "related_skills": normalize_text_list(related_skills),
            }

        def skill_relative_path(skill_file, root):
            return skill_file.parent.relative_to(root).as_posix()

        def skill_category(relative_path):
            if "/" not in relative_path:
                return None
            return relative_path.rsplit("/", 1)[0]

        def feature_flags(skill_dir):
            return {
                "has_references": (skill_dir / "references").is_dir(),
                "has_scripts": (skill_dir / "scripts").is_dir(),
                "has_templates": (skill_dir / "templates").is_dir(),
            }

        def build_skill_summary(skill_file, root):
            content = skill_file.read_text(encoding="utf-8", errors="replace")
            relative_path = skill_relative_path(skill_file, root)
            category = skill_category(relative_path)
            parsed = parse_frontmatter(content)
            slug = skill_file.parent.name
            flags = feature_flags(skill_file.parent)

            return {
                "id": relative_path,
                "slug": slug,
                "category": category,
                "relative_path": relative_path,
                "name": parsed["name"],
                "description": parsed["description"],
                "version": parsed["version"],
                "tags": parsed["tags"],
                "related_skills": parsed["related_skills"],
                "has_references": flags["has_references"],
                "has_scripts": flags["has_scripts"],
                "has_templates": flags["has_templates"],
            }

        def skill_sort_key(item):
            return (
                (item.get("category") or "").casefold(),
                (item.get("name") or item.get("slug") or "").casefold(),
                item.get("relative_path", "").casefold(),
            )

        def discover_skill_items():
            root = skills_root()
            if not root.exists():
                return []

            items = []
            for skill_file in sorted(root.rglob("SKILL.md")):
                if not skill_file.is_file():
                    continue
                try:
                    items.append(build_skill_summary(skill_file, root))
                except Exception:
                    continue

            items.sort(key=skill_sort_key)
            return items

        def resolve_skill_file(relative_path):
            normalized = pathlib.PurePosixPath(relative_path)
            if normalized.is_absolute() or ".." in normalized.parts or not normalized.parts:
                fail("The requested skill path is invalid.")

            root = skills_root().resolve()
            target = (root / pathlib.Path(*normalized.parts) / "SKILL.md").resolve()

            try:
                target.relative_to(root)
            except ValueError:
                fail("The requested skill path escapes the Hermes skills directory.")

            return target, root

        def build_skill_detail(relative_path):
            skill_file, root = resolve_skill_file(relative_path)
            if not skill_file.exists():
                fail(f"No skill exists at {relative_path}.")
            if not skill_file.is_file():
                fail(f"{relative_path} does not resolve to a readable SKILL.md file.")

            content = skill_file.read_text(encoding="utf-8", errors="replace")
            summary = build_skill_summary(skill_file, root)
            summary["markdown_content"] = content
            summary["content_hash"] = hashlib.sha256(skill_file.read_bytes()).hexdigest()
            return summary
        """
    }
}

private struct EmptySkillRequest: Encodable {
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case hermesHome = "hermes_home"
    }
}

private struct SkillDetailRequest: Encodable {
    let relativePath: String
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case hermesHome = "hermes_home"
    }
}

private struct SkillWriteRequest: Encodable {
    let relativePath: String
    let markdownContent: String
    let expectedContentHash: String?
    let createReferencesFolder: Bool
    let createScriptsFolder: Bool
    let createTemplatesFolder: Bool
    let hermesHome: String

    enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case markdownContent = "markdown_content"
        case expectedContentHash = "expected_content_hash"
        case createReferencesFolder = "create_references_folder"
        case createScriptsFolder = "create_scripts_folder"
        case createTemplatesFolder = "create_templates_folder"
        case hermesHome = "hermes_home"
    }
}
