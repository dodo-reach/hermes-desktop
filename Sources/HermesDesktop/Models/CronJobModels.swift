import Foundation

struct CronJobListResponse: Codable {
    let ok: Bool
    let jobs: [CronJob]
}

struct CronJob: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let prompt: String
    let skills: [String]
    let model: String?
    let provider: String?
    let baseURL: String?
    let schedule: CronSchedule?
    let scheduleDisplay: String
    let recurrence: CronRecurrence?
    let enabled: Bool
    let state: String
    let createdAt: Date?
    let nextRunAt: Date?
    let lastRunAt: Date?
    let lastStatus: String?
    let lastError: String?
    let deliveryTarget: String?
    let origin: CronJobOrigin?
    let lastDeliveryError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case skills
        case model
        case provider
        case baseURL = "base_url"
        case schedule
        case scheduleDisplay = "schedule_display"
        case recurrence
        case enabled
        case state
        case createdAt = "created_at"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case deliveryTarget = "delivery_target"
        case origin
        case lastDeliveryError = "last_delivery_error"
    }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var trimmedPrompt: String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var previewPrompt: String {
        guard let trimmedPrompt else {
            return "No saved prompt payload"
        }

        let compact = trimmedPrompt.replacingOccurrences(of: "\n", with: " ")
        return compact.count > 140 ? String(compact.prefix(140)) + "…" : compact
    }

    var resolvedScheduleDisplay: String {
        if let rawScheduleText {
            return CronScheduleFormatter.humanReadableDescription(for: rawScheduleText) ?? rawScheduleText
        }

        return "No schedule metadata"
    }

    var isPaused: Bool {
        normalizedState == "paused"
    }

    var isRunning: Bool {
        normalizedState == "running"
    }

    var isActive: Bool {
        isRunning || normalizedState == "scheduled"
    }

    var displayState: String {
        switch normalizedState {
        case "scheduled":
            return "Active"
        case "":
            return enabled ? "Active" : "Paused"
        default:
            return normalizedState
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var displayModel: String? {
        guard let model,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if model.count <= 34 {
            return model
        }

        let prefix = model.prefix(16)
        let suffix = model.suffix(12)
        return "\(prefix)…\(suffix)"
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let normalizedQuery = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let haystacks = [
            id,
            resolvedName,
            prompt,
            resolvedScheduleDisplay,
            rawScheduleText ?? "",
            model ?? "",
            provider ?? "",
            baseURL ?? "",
            deliveryTarget ?? ""
        ] + skills

        return haystacks.contains { value in
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .localizedStandardContains(normalizedQuery)
        }
    }

    private var normalizedState: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var rawScheduleText: String? {
        let expr = schedule?.expr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !expr.isEmpty {
            return expr
        }

        let display = scheduleDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? nil : display
    }
}

struct CronSchedule: Codable, Hashable {
    let kind: String?
    let expr: String?
    let timezone: String?
}

struct CronRecurrence: Codable, Hashable {
    let times: Int?
    let remaining: Int?
}

struct CronJobOrigin: Codable, Hashable {
    let kind: String?
    let source: String?
    let label: String?
}

enum CronSchedulePreset: String, CaseIterable, Identifiable {
    case afterDelay
    case atDateTime
    case everyInterval
    case hourly
    case daily
    case weekdays
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .afterDelay:
            return "One Time After"
        case .atDateTime:
            return "One Time At"
        case .everyInterval:
            return "Every"
        case .hourly:
            return "Hourly"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom"
        }
    }
}

enum CronIntervalUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .minutes:
            return "m"
        case .hours:
            return "h"
        case .days:
            return "d"
        }
    }

    var title: String {
        switch self {
        case .minutes:
            return "Minutes"
        case .hours:
            return "Hours"
        case .days:
            return "Days"
        }
    }

    func displayLabel(for value: Int) -> String {
        switch self {
        case .minutes:
            return value == 1 ? "minute" : "minutes"
        case .hours:
            return value == 1 ? "hour" : "hours"
        case .days:
            return value == 1 ? "day" : "days"
        }
    }
}

enum CronDeliveryPreset: String, CaseIterable, Identifiable {
    case local
    case origin
    case telegram
    case discord
    case slack
    case whatsapp
    case email
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local:
            return "Local Only"
        case .origin:
            return "Origin Chat"
        case .telegram:
            return "Telegram Home"
        case .discord:
            return "Discord Home"
        case .slack:
            return "Slack Home"
        case .whatsapp:
            return "WhatsApp Home"
        case .email:
            return "Email"
        case .custom:
            return "Custom Target"
        }
    }

    var resolvedValue: String? {
        switch self {
        case .local:
            return "local"
        case .origin:
            return "origin"
        case .telegram:
            return "telegram"
        case .discord:
            return "discord"
        case .slack:
            return "slack"
        case .whatsapp:
            return "whatsapp"
        case .email:
            return "email"
        case .custom:
            return nil
        }
    }

    static func from(deliveryTarget: String?) -> (preset: CronDeliveryPreset, customValue: String) {
        let trimmed = deliveryTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return (.custom, "")
        }

        switch trimmed {
        case "local":
            return (.local, "")
        case "origin":
            return (.origin, "")
        case "telegram":
            return (.telegram, "")
        case "discord":
            return (.discord, "")
        case "slack":
            return (.slack, "")
        case "whatsapp":
            return (.whatsapp, "")
        case "email":
            return (.email, "")
        default:
            return (.custom, trimmed)
        }
    }
}

struct CronScheduleDraft: Hashable {
    var preset: CronSchedulePreset
    var hour: Int
    var minute: Int
    var weekday: Int
    var dayOfMonth: Int
    var intervalValue: Int
    var intervalUnit: CronIntervalUnit
    var oneTimeDate: Date
    var customExpression: String

    init(
        preset: CronSchedulePreset = .daily,
        hour: Int = 9,
        minute: Int = 0,
        weekday: Int = 1,
        dayOfMonth: Int = 1,
        intervalValue: Int = 1,
        intervalUnit: CronIntervalUnit = .hours,
        oneTimeDate: Date = Date().addingTimeInterval(3600),
        customExpression: String = ""
    ) {
        self.preset = preset
        self.hour = max(0, min(hour, 23))
        self.minute = max(0, min(minute, 59))
        self.weekday = max(0, min(weekday, 6))
        self.dayOfMonth = max(1, min(dayOfMonth, 31))
        self.intervalValue = max(1, intervalValue)
        self.intervalUnit = intervalUnit
        self.oneTimeDate = oneTimeDate
        self.customExpression = customExpression
    }

    init(job: CronJob) {
        self = Self.from(expression: job.rawScheduleText)
    }

    static func from(expression: String?) -> CronScheduleDraft {
        guard let expression else { return CronScheduleDraft() }

        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (value, unit) = CronScheduleFormatter.oneTimeDelayComponents(from: trimmed) {
            return CronScheduleDraft(
                preset: .afterDelay,
                intervalValue: value,
                intervalUnit: unit,
                customExpression: trimmed
            )
        }

        if let (value, unit) = CronScheduleFormatter.intervalComponents(from: trimmed) {
            return CronScheduleDraft(
                preset: .everyInterval,
                intervalValue: value,
                intervalUnit: unit,
                customExpression: trimmed
            )
        }

        if let date = CronScheduleFormatter.date(from: trimmed) {
            return CronScheduleDraft(
                preset: .atDateTime,
                oneTimeDate: date,
                customExpression: trimmed
            )
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return CronScheduleDraft(preset: .custom, customExpression: trimmed)
        }

        let minute = Int(parts[0])
        let hour = Int(parts[1])
        let dayOfMonth = Int(parts[2])
        let month = parts[3]
        let dayOfWeek = parts[4]

        if parts[2] == "*",
           month == "*",
           dayOfWeek == "*",
           let minute,
           parts[1] == "*" {
            return CronScheduleDraft(
                preset: .hourly,
                minute: minute,
                customExpression: trimmed
            )
        }

        guard let minute, let hour, month == "*" else {
            return CronScheduleDraft(preset: .custom, customExpression: trimmed)
        }

        if parts[2] == "*", dayOfWeek == "*" {
            return CronScheduleDraft(
                preset: .daily,
                hour: hour,
                minute: minute,
                customExpression: trimmed
            )
        }

        if parts[2] == "*", dayOfWeek == "1-5" {
            return CronScheduleDraft(
                preset: .weekdays,
                hour: hour,
                minute: minute,
                customExpression: trimmed
            )
        }

        if parts[2] == "*",
           let weekday = CronScheduleFormatter.weekdayIndex(for: dayOfWeek) {
            return CronScheduleDraft(
                preset: .weekly,
                hour: hour,
                minute: minute,
                weekday: weekday,
                customExpression: trimmed
            )
        }

        if dayOfWeek == "*",
           let dayOfMonth {
            return CronScheduleDraft(
                preset: .monthly,
                hour: hour,
                minute: minute,
                dayOfMonth: dayOfMonth,
                customExpression: trimmed
            )
        }

        return CronScheduleDraft(preset: .custom, customExpression: trimmed)
    }

    var expression: String? {
        switch preset {
        case .afterDelay:
            return "\(intervalValue)\(intervalUnit.shortLabel)"
        case .atDateTime:
            return CronScheduleFormatter.localTimestampString(from: oneTimeDate)
        case .everyInterval:
            return "every \(intervalValue)\(intervalUnit.shortLabel)"
        case .hourly:
            return String(format: "%d * * * *", minute)
        case .daily:
            return String(format: "%d %d * * *", minute, hour)
        case .weekdays:
            return String(format: "%d %d * * 1-5", minute, hour)
        case .weekly:
            return String(format: "%d %d * * %d", minute, hour, weekday)
        case .monthly:
            return String(format: "%d %d %d * *", minute, hour, dayOfMonth)
        case .custom:
            let trimmed = customExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var scheduleKind: String? {
        switch preset {
        case .afterDelay:
            return "delay"
        case .atDateTime:
            return "at"
        case .everyInterval:
            return "every"
        case .hourly, .daily, .weekdays, .weekly, .monthly:
            return "cron"
        case .custom:
            guard let expression else { return nil }
            let parts = expression.split(whereSeparator: \.isWhitespace)
            return parts.count == 5 ? "cron" : nil
        }
    }

    var repeatTimes: Int? {
        switch preset {
        case .afterDelay, .atDateTime:
            return 1
        default:
            return nil
        }
    }

    var summary: String {
        guard let expression else { return "No schedule" }
        return CronScheduleFormatter.humanReadableDescription(for: expression) ?? expression
    }
}

struct CronJobDraft: Hashable {
    var name: String
    var prompt: String
    var skillsText: String
    var model: String
    var provider: String
    var baseURL: String
    var deliveryPreset: CronDeliveryPreset
    var customDeliveryTarget: String
    var timezone: String
    var schedule: CronScheduleDraft

    init(
        name: String = "",
        prompt: String = "",
        skillsText: String = "",
        model: String = "",
        provider: String = "",
        baseURL: String = "",
        deliveryPreset: CronDeliveryPreset = .local,
        customDeliveryTarget: String = "",
        timezone: String = "",
        schedule: CronScheduleDraft = CronScheduleDraft()
    ) {
        self.name = name
        self.prompt = prompt
        self.skillsText = skillsText
        self.model = model
        self.provider = provider
        self.baseURL = baseURL
        self.deliveryPreset = deliveryPreset
        self.customDeliveryTarget = customDeliveryTarget
        self.timezone = timezone
        self.schedule = schedule
    }

    init(job: CronJob) {
        let parsedDelivery = CronDeliveryPreset.from(deliveryTarget: job.deliveryTarget)
        self.name = job.resolvedName
        self.prompt = job.trimmedPrompt ?? job.prompt
        self.skillsText = job.skills.joined(separator: ", ")
        self.model = job.model ?? ""
        self.provider = job.provider ?? ""
        self.baseURL = job.baseURL ?? ""
        self.deliveryPreset = parsedDelivery.preset
        self.customDeliveryTarget = parsedDelivery.customValue
        self.timezone = job.schedule?.timezone ?? ""
        self.schedule = CronScheduleDraft(job: job)
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedSkills: [String] {
        skillsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedModel: String? {
        normalizedOptional(model)
    }

    var normalizedProvider: String? {
        normalizedOptional(provider)
    }

    var normalizedBaseURL: String? {
        normalizedOptional(baseURL)
    }

    var normalizedDeliveryTarget: String? {
        if let resolvedValue = deliveryPreset.resolvedValue {
            return resolvedValue
        }

        return normalizedOptional(customDeliveryTarget)
    }

    var normalizedTimezone: String? {
        switch schedule.preset {
        case .afterDelay, .atDateTime, .everyInterval:
            return nil
        case .hourly, .daily, .weekdays, .weekly, .monthly, .custom:
            break
        }
        return normalizedOptional(timezone)
    }

    var validationError: String? {
        if normalizedName.isEmpty {
            return "A cron job title is required."
        }

        if normalizedPrompt.isEmpty {
            return "A prompt is required."
        }

        guard let expression = schedule.expression else {
            return "A valid schedule is required."
        }

        if expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A valid schedule is required."
        }

        if normalizedDeliveryTarget == nil {
            return "A delivery target is required."
        }

        return nil
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CronScheduleFormatter {
    private static let weekdaySymbols = [
        "0": "Sun",
        "1": "Mon",
        "2": "Tue",
        "3": "Wed",
        "4": "Thu",
        "5": "Fri",
        "6": "Sat",
        "7": "Sun",
        "sun": "Sun",
        "mon": "Mon",
        "tue": "Tue",
        "wed": "Wed",
        "thu": "Thu",
        "fri": "Fri",
        "sat": "Sat"
    ]

    static let weekdayPickerLabels = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday"
    ]

    static func humanReadableDescription(for expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        if let (value, unit) = oneTimeDelayComponents(from: trimmed) {
            return "Once in \(value) \(unit.displayLabel(for: value))"
        }

        if let (value, unit) = intervalComponents(from: trimmed) {
            return "Every \(value) \(unit.displayLabel(for: value))"
        }

        if let date = date(from: trimmed) {
            return "Once on \(DateFormatters.shortDateTimeFormatter().string(from: date))"
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { return nil }

        let minute = parts[0]
        let hour = parts[1]
        let dayOfMonth = parts[2]
        let month = parts[3]
        let dayOfWeek = parts[4]

        guard let time = formattedTime(hour: hour, minute: minute) else {
            return nil
        }

        if dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return "Every day at \(time)"
        }

        if dayOfMonth == "*", month == "*", dayOfWeek == "1-5" {
            return "Every weekday at \(time)"
        }

        if dayOfMonth == "*", month == "*",
           let days = formattedWeekdays(dayOfWeek) {
            return "Every \(days) at \(time)"
        }

        if hour == "*", month == "*", dayOfMonth == "*", dayOfWeek == "*",
           let minuteValue = Int(minute) {
            return String(format: "Every hour at :%02d", minuteValue)
        }

        if month == "*", dayOfWeek == "*",
           let day = Int(dayOfMonth) {
            return "On day \(day) of every month at \(time)"
        }

        return nil
    }

    private static func formattedTime(hour: String, minute: String) -> String? {
        guard let hourValue = Int(hour), let minuteValue = Int(minute),
              (0...23).contains(hourValue), (0...59).contains(minuteValue) else {
            return nil
        }

        return String(format: "%02d:%02d", hourValue, minuteValue)
    }

    private static func formattedWeekdays(_ rawValue: String) -> String? {
        let values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard !values.isEmpty else { return nil }

        let resolved = values.compactMap { weekdaySymbols[$0] }
        guard resolved.count == values.count else { return nil }

        return resolved.joined(separator: ", ")
    }

    static func weekdayIndex(for rawValue: String) -> Int? {
        let lowered = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch lowered {
        case "0", "7", "sun":
            return 0
        case "1", "mon":
            return 1
        case "2", "tue":
            return 2
        case "3", "wed":
            return 3
        case "4", "thu":
            return 4
        case "5", "fri":
            return 5
        case "6", "sat":
            return 6
        default:
            return nil
        }
    }

    static func oneTimeDelayComponents(from value: String) -> (Int, CronIntervalUnit)? {
        durationComponents(from: value)
    }

    static func intervalComponents(from value: String) -> (Int, CronIntervalUnit)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("every ") else { return nil }
        return durationComponents(from: String(trimmed.dropFirst(6)))
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ISO8601DateFormatter.fractionalSecondsFormatter().date(from: trimmed) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }
        return localTimestampFormatter.date(from: trimmed)
    }

    static func localTimestampString(from date: Date) -> String {
        localTimestampFormatter.string(from: date)
    }

    private static func durationComponents(from value: String) -> (Int, CronIntervalUnit)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2,
              let quantity = Int(trimmed.dropLast()) else {
            return nil
        }

        switch trimmed.suffix(1) {
        case "m":
            return (quantity, .minutes)
        case "h":
            return (quantity, .hours)
        case "d":
            return (quantity, .days)
        default:
            return nil
        }
    }

    private static let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
