import Foundation

final class CronBrowserService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func listJobs(connection: ConnectionProfile) async throws -> [CronJob] {
        let script = try RemotePythonScript.wrap(EmptyCronRequest(), body: listJobsBody)
        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: "python3 -",
            standardInput: Data(script.utf8),
            allocateTTY: false
        )

        try sshTransport.validateSuccessfulExit(result, for: connection)

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Remote cron output was not valid UTF-8.")
        }

        do {
            return try makeDecoder().decode(CronJobListResponse.self, from: data).jobs
        } catch {
            throw SSHTransportError.invalidResponse(
                "Failed to decode remote cron metadata: \(error.localizedDescription)\n\n\(result.stdout)"
            )
        }
    }

    func pauseJob(connection: ConnectionProfile, jobID: String) async throws {
        try await performCommand(connection: connection, jobID: jobID, command: .pause)
    }

    func createJob(connection: ConnectionProfile, draft: CronJobDraft) async throws -> String {
        let response = try await performMutation(
            connection: connection,
            request: CronMutationRequest(
                action: .create,
                draft: CronMutationDraft(draft: draft)
            )
        )

        guard let jobID = response.jobID else {
            throw SSHTransportError.invalidResponse("The remote cron create command did not return a job ID.")
        }

        return jobID
    }

    func updateJob(connection: ConnectionProfile, jobID: String, draft: CronJobDraft) async throws {
        _ = try await performMutation(
            connection: connection,
            request: CronMutationRequest(
                action: .update,
                jobID: jobID,
                draft: CronMutationDraft(draft: draft)
            )
        )
    }

    func resumeJob(connection: ConnectionProfile, jobID: String) async throws {
        try await performCommand(connection: connection, jobID: jobID, command: .resume)
    }

    func removeJob(connection: ConnectionProfile, jobID: String) async throws {
        try await performCommand(connection: connection, jobID: jobID, command: .remove)
    }

    func runJobNow(connection: ConnectionProfile, jobID: String) async throws {
        try await performCommand(connection: connection, jobID: jobID, command: .run)
    }

    private func performCommand(
        connection: ConnectionProfile,
        jobID: String,
        command: CronCommand
    ) async throws {
        let script = try RemotePythonScript.wrap(
            CronCommandRequest(jobID: jobID, command: command.rawValue),
            body: commandBody
        )

        _ = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: CronCommandResponse.self
        )
    }

    private func performMutation(
        connection: ConnectionProfile,
        request: CronMutationRequest
    ) async throws -> CronMutationResponse {
        let script = try RemotePythonScript.wrap(request, body: mutationBody)
        return try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: CronMutationResponse.self
        )
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.fractionalSecondsFormatter().date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    private var listJobsBody: String {
        """
        import json
        import pathlib
        import sys
        from datetime import datetime, timezone

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def normalize_text(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                value = value.decode("utf-8", errors="replace")
            value = str(value).strip()
            return value or None

        def normalize_bool(value):
            if isinstance(value, bool):
                return value
            if value is None:
                return None

            lowered = str(value).strip().lower()
            if lowered in {"1", "true", "yes", "on"}:
                return True
            if lowered in {"0", "false", "no", "off"}:
                return False
            return None

        def normalize_list(value):
            if value is None:
                return []
            if isinstance(value, (list, tuple, set)):
                items = []
                for item in value:
                    normalized = normalize_text(item)
                    if normalized is not None:
                        items.append(normalized)
                return items

            normalized = normalize_text(value)
            return [normalized] if normalized is not None else []

        def first_text(*values):
            for value in values:
                normalized = normalize_text(value)
                if normalized is not None:
                    return normalized
            return None

        def first_int(*values):
            for value in values:
                if value is None:
                    continue
                try:
                    return int(value)
                except Exception:
                    continue
            return None

        def normalize_date(value):
            if value is None:
                return None
            if isinstance(value, (int, float)):
                return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat()

            text = normalize_text(value)
            if text is None:
                return None

            try:
                return datetime.fromtimestamp(float(text), tz=timezone.utc).isoformat()
            except Exception:
                return text

        def normalize_state(item):
            raw_state = first_text(
                item.get("state"),
                item.get("status"),
                item.get("job_state"),
            )
            if raw_state is not None:
                return raw_state.lower()

            if item.get("paused_at") is not None:
                return "paused"
            if normalize_bool(item.get("running")) is True:
                return "running"
            if normalize_bool(item.get("enabled")) is False:
                return "paused"
            return "scheduled"

        def normalize_schedule(item):
            schedule = item.get("schedule") if isinstance(item.get("schedule"), dict) else {}
            expr = first_text(
                schedule.get("expr"),
                schedule.get("expression"),
                item.get("cron"),
                item.get("schedule_expr"),
            )
            schedule_display = first_text(
                item.get("schedule_display"),
                item.get("scheduleDisplay"),
                schedule.get("display"),
                schedule.get("summary"),
                expr,
            ) or "Custom schedule"

            normalized_schedule = {
                "kind": first_text(schedule.get("kind"), item.get("schedule_kind")),
                "expr": expr,
                "timezone": first_text(schedule.get("timezone"), schedule.get("tz"), item.get("timezone")),
            }

            if normalized_schedule["kind"] is None and normalized_schedule["expr"] is None and normalized_schedule["timezone"] is None:
                normalized_schedule = None

            return normalized_schedule, schedule_display

        def normalize_recurrence(item):
            recurrence = item.get("recurrence")
            if not isinstance(recurrence, dict):
                recurrence = item.get("repeat")
            if not isinstance(recurrence, dict):
                return None

            times = first_int(recurrence.get("times"))
            remaining = first_int(recurrence.get("remaining"), recurrence.get("remaining_runs"))

            if times is None and remaining is None:
                return None

            return {
                "times": times,
                "remaining": remaining,
            }

        def normalize_origin(item):
            origin = item.get("origin")
            if not isinstance(origin, dict):
                return None

            normalized = {
                "kind": first_text(origin.get("kind"), origin.get("type")),
                "source": first_text(origin.get("source"), origin.get("path")),
                "label": first_text(origin.get("label"), origin.get("name")),
            }

            if normalized["kind"] is None and normalized["source"] is None and normalized["label"] is None:
                return None

            return normalized

        def delivery_target(item, payload):
            delivery = item.get("delivery")
            if isinstance(delivery, dict):
                return first_text(delivery.get("target"), delivery.get("destination"), delivery.get("mode"))

            return first_text(
                item.get("deliver"),
                item.get("delivery_target"),
                delivery,
                payload.get("deliver") if isinstance(payload, dict) else None,
            )

        def normalize_job(item):
            if not isinstance(item, dict):
                return None

            job_id = first_text(item.get("id"), item.get("job_id"), item.get("slug"))
            if job_id is None:
                return None

            payload_data = item.get("payload")
            payload = payload_data if isinstance(payload_data, dict) else {}
            prompt = first_text(
                item.get("prompt"),
                item.get("message"),
                payload.get("prompt"),
                payload.get("message"),
                payload.get("task"),
            ) or ""

            name = first_text(
                item.get("name"),
                item.get("title"),
                payload.get("name"),
                prompt.splitlines()[0] if prompt else None,
                job_id,
            ) or job_id

            skills = normalize_list(item.get("skills"))
            if not skills:
                skills = normalize_list(payload.get("skills"))

            schedule, schedule_display = normalize_schedule(item)
            state = normalize_state(item)
            enabled = normalize_bool(item.get("enabled"))
            if enabled is None:
                enabled = state != "paused"

            return {
                "id": job_id,
                "name": name,
                "prompt": prompt,
                "skills": skills,
                "model": first_text(item.get("model"), payload.get("model")),
                "provider": first_text(item.get("provider"), item.get("billing_provider"), payload.get("provider")),
                "base_url": first_text(item.get("base_url"), payload.get("base_url")),
                "schedule": schedule,
                "schedule_display": schedule_display,
                "recurrence": normalize_recurrence(item),
                "enabled": enabled,
                "state": state,
                "created_at": normalize_date(item.get("created_at")),
                "next_run_at": normalize_date(item.get("next_run_at")),
                "last_run_at": normalize_date(item.get("last_run_at")),
                "last_status": first_text(item.get("last_status"), item.get("run_status")),
                "last_error": first_text(item.get("last_error"), item.get("error")),
                "delivery_target": delivery_target(item, payload),
                "origin": normalize_origin(item),
                "last_delivery_error": first_text(item.get("last_delivery_error")),
            }

        try:
            jobs_path = pathlib.Path.home() / ".hermes" / "cron" / "jobs.json"
            if not jobs_path.exists():
                print(json.dumps({
                    "ok": True,
                    "jobs": [],
                }, ensure_ascii=False))
                sys.exit(0)

            raw_data = json.loads(jobs_path.read_text(encoding="utf-8"))
            if isinstance(raw_data, dict):
                raw_jobs = raw_data.get("jobs") or raw_data.get("items") or raw_data.get("cron_jobs") or []
            elif isinstance(raw_data, list):
                raw_jobs = raw_data
            else:
                fail(f"Unsupported cron metadata format in {jobs_path}.")

            jobs = []
            for item in raw_jobs:
                normalized = normalize_job(item)
                if normalized is not None:
                    jobs.append(normalized)

            jobs.sort(
                key=lambda item: (
                    item.get("next_run_at") is None,
                    item.get("next_run_at") or "",
                    item.get("name", "").lower(),
                )
            )

            print(json.dumps({
                "ok": True,
                "jobs": jobs,
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to read the remote Hermes cron jobs: {exc}")
        """
    }

    private var commandBody: String {
        """
        import json
        import os
        import pathlib
        import shutil
        import subprocess
        import sys

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def find_hermes_binary():
            candidate = shutil.which("hermes")
            if candidate:
                return candidate

            fallback = pathlib.Path.home() / ".local" / "bin" / "hermes"
            if fallback.exists() and os.access(fallback, os.X_OK):
                return str(fallback)

            return None

        job_id = str(payload.get("job_id") or "").strip()
        command = str(payload.get("command") or "").strip()

        if not job_id:
            fail("The cron job ID is required.")
        if not command:
            fail("The cron command is required.")

        hermes_binary = find_hermes_binary()
        if hermes_binary is None:
            fail("Hermes CLI was not found on the active host.")

        try:
            completed = subprocess.run(
                [hermes_binary, "cron", command, job_id],
                capture_output=True,
                text=True,
            )
        except Exception as exc:
            fail(f"Unable to launch Hermes CLI: {exc}")

        if completed.returncode != 0:
            message = (completed.stderr or completed.stdout or f"Hermes cron {command} failed.").strip()
            fail(message)

        print(json.dumps({
            "ok": True,
            "message": (completed.stdout or "").strip() or None,
        }, ensure_ascii=False))
        """
    }

    private var mutationBody: String {
        """
        import json
        import pathlib
        import re
        import secrets
        import sys
        from datetime import datetime, timezone

        def fail(message):
            print(json.dumps({
                "ok": False,
                "error": message,
            }, ensure_ascii=False))
            sys.exit(1)

        def normalize_text(value):
            if value is None:
                return None
            if isinstance(value, bytes):
                value = value.decode("utf-8", errors="replace")
            value = str(value).strip()
            return value or None

        def normalize_list(value):
            if value is None:
                return []
            if isinstance(value, (list, tuple, set)):
                items = []
                for item in value:
                    normalized = normalize_text(item)
                    if normalized is not None:
                        items.append(normalized)
                return items
            normalized = normalize_text(value)
            return [normalized] if normalized is not None else []

        def load_container(path):
            if not path.exists():
                return [], "list", None

            raw = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(raw, list):
                return raw, "list", None

            if isinstance(raw, dict):
                for key in ("jobs", "items", "cron_jobs"):
                    jobs = raw.get(key)
                    if isinstance(jobs, list):
                        return jobs, "dict", key
                fail(f"Unsupported cron metadata wrapper in {path}.")

            fail(f"Unsupported cron metadata format in {path}.")

        def save_container(path, jobs, container_kind, container_key):
            if container_kind == "list":
                payload_to_write = jobs
            else:
                payload_to_write = {container_key or "jobs": jobs}

            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                json.dumps(payload_to_write, ensure_ascii=False, indent=2) + "\\n",
                encoding="utf-8"
            )

        def iso_now():
            return datetime.now(timezone.utc).isoformat()

        def detect_schedule(value):
            if value is None:
                return None, None

            text = value.strip()
            lowered = text.lower()

            if re.fullmatch(r"\\d+[mhd]", lowered):
                return "delay", 1

            if re.fullmatch(r"every\\s+\\d+[mhd]", lowered):
                return "every", None

            try:
                datetime.fromisoformat(text.replace("Z", "+00:00"))
                return "at", 1
            except Exception:
                pass

            if len(text.split()) == 5:
                return "cron", None

            return None, None

        action = normalize_text(payload.get("action"))
        if action not in {"create", "update"}:
            fail("Unsupported cron mutation action.")

        draft = payload.get("draft")
        if not isinstance(draft, dict):
            fail("A cron draft payload is required.")

        name = normalize_text(draft.get("name"))
        prompt_text = normalize_text(draft.get("prompt"))
        schedule_expr = normalize_text(draft.get("schedule"))
        skills = normalize_list(draft.get("skills"))
        model = normalize_text(draft.get("model"))
        provider = normalize_text(draft.get("provider"))
        base_url = normalize_text(draft.get("base_url"))
        delivery = normalize_text(draft.get("deliver"))
        timezone_name = normalize_text(draft.get("timezone"))
        schedule_kind, repeat_times = detect_schedule(schedule_expr)

        if name is None:
            fail("The cron job title is required.")
        if prompt_text is None:
            fail("The cron job prompt is required.")
        if schedule_expr is None:
            fail("The cron job schedule is required.")
        if delivery is None:
            fail("A delivery target is required.")

        jobs_path = pathlib.Path.home() / ".hermes" / "cron" / "jobs.json"
        jobs, container_kind, container_key = load_container(jobs_path)

        if action == "create":
            existing_ids = {
                normalize_text(item.get("id"))
                for item in jobs
                if isinstance(item, dict)
            }
            job_id = secrets.token_hex(6)
            while job_id in existing_ids:
                job_id = secrets.token_hex(6)

            job = {
                "id": job_id,
                "name": name,
                "prompt": prompt_text,
                "skills": skills,
                "skill": skills[0] if len(skills) == 1 else None,
                "model": model,
                "provider": provider,
                "base_url": base_url,
                "schedule": {
                    "kind": schedule_kind,
                    "expr": schedule_expr,
                    "timezone": timezone_name,
                    "display": schedule_expr,
                },
                "schedule_display": schedule_expr,
                "repeat": {
                    "times": repeat_times,
                    "completed": 0,
                },
                "enabled": True,
                "state": "scheduled",
                "paused_at": None,
                "paused_reason": None,
                "created_at": iso_now(),
                "next_run_at": None,
                "last_run_at": None,
                "last_status": None,
                "last_error": None,
                "deliver": delivery,
                "origin": {
                    "platform": "desktop",
                    "chat_name": "Hermes Desktop",
                },
            }
            jobs.append(job)
            save_container(jobs_path, jobs, container_kind, container_key)
            print(json.dumps({
                "ok": True,
                "job_id": job_id,
            }, ensure_ascii=False))
            sys.exit(0)

        job_id = normalize_text(payload.get("job_id"))
        if job_id is None:
            fail("The cron job ID is required.")

        target = None
        for item in jobs:
            if not isinstance(item, dict):
                continue
            if normalize_text(item.get("id")) == job_id:
                target = item
                break

        if target is None:
            fail(f"Cron job {job_id} was not found.")

        old_expr = normalize_text(
            ((target.get("schedule") or {}).get("expr")) if isinstance(target.get("schedule"), dict) else None
        )
        schedule_changed = old_expr != schedule_expr

        target["name"] = name
        target["prompt"] = prompt_text
        target["skills"] = skills
        target["skill"] = skills[0] if len(skills) == 1 else None
        target["model"] = model
        target["provider"] = provider
        target["base_url"] = base_url
        target["deliver"] = delivery

        schedule_data = target.get("schedule")
        if not isinstance(schedule_data, dict):
            schedule_data = {}
        schedule_data["kind"] = schedule_kind
        schedule_data["expr"] = schedule_expr
        schedule_data["timezone"] = timezone_name
        schedule_data["display"] = schedule_expr
        target["schedule"] = schedule_data
        target["schedule_display"] = schedule_expr

        repeat_data = target.get("repeat")
        if not isinstance(repeat_data, dict):
            repeat_data = {}
        repeat_data["times"] = repeat_times
        if schedule_changed:
            repeat_data["completed"] = 0
        elif "completed" not in repeat_data:
            repeat_data["completed"] = 0
        target["repeat"] = repeat_data

        if schedule_changed:
            target["next_run_at"] = None
            if normalize_text(target.get("state")) != "paused":
                target["state"] = "scheduled"
            if target.get("enabled") is not False:
                target["enabled"] = True

        save_container(jobs_path, jobs, container_kind, container_key)
        print(json.dumps({
            "ok": True,
            "job_id": job_id,
        }, ensure_ascii=False))
        """
    }
}

private struct EmptyCronRequest: Encodable {}

private struct CronCommandRequest: Encodable {
    let jobID: String
    let command: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case command
    }
}

private struct CronCommandResponse: Decodable {
    let ok: Bool
    let message: String?
}

private struct CronMutationRequest: Encodable {
    let action: CronMutationAction
    var jobID: String?
    let draft: CronMutationDraft

    enum CodingKeys: String, CodingKey {
        case action
        case jobID = "job_id"
        case draft
    }
}

private struct CronMutationDraft: Encodable {
    let name: String
    let prompt: String
    let schedule: String
    let skills: [String]
    let model: String?
    let provider: String?
    let baseURL: String?
    let deliver: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case name
        case prompt
        case schedule
        case skills
        case model
        case provider
        case baseURL = "base_url"
        case deliver
        case timezone
    }

    init(draft: CronJobDraft) {
        self.name = draft.normalizedName
        self.prompt = draft.normalizedPrompt
        self.schedule = draft.schedule.expression ?? ""
        self.skills = draft.normalizedSkills
        self.model = draft.normalizedModel
        self.provider = draft.normalizedProvider
        self.baseURL = draft.normalizedBaseURL
        self.deliver = draft.normalizedDeliveryTarget
        self.timezone = draft.normalizedTimezone
    }
}

private struct CronMutationResponse: Decodable {
    let ok: Bool
    let jobID: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case jobID = "job_id"
    }
}

private enum CronCommand: String {
    case pause
    case resume
    case run
    case remove
}

private enum CronMutationAction: String, Encodable {
    case create
    case update
}
