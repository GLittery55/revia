import Foundation
import HealthKit
import EventKit

struct CardService {
    func draw() -> ReflectionCard {
        let index = Int.random(in: 0..<22)
        return ReflectionCard(id: index, neutralLabel: String(format: "Reflection Card %02d", index + 1), imageName: String(format: "m%02d", index))
    }
}

struct SafetyService {
    private let signals = ["自杀", "不想活", "结束生命", "伤害自己", "suicide", "kill myself", "self-harm"]
    func requiresInterrupt(_ text: String) -> Bool { signals.contains { text.localizedCaseInsensitiveContains($0) } }
}

actor SessionStore {
    private let directory: URL
    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReflectionSessions", isDirectory: true)
    }
    func save(_ session: ReflectionSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: directory.appendingPathComponent("\(session.id.uuidString).json"), options: .atomic)
    }
    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

actor HealthKitService {
    private let store = HKHealthStore()
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeart = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        try? await store.requestAuthorization(toShare: [], read: [sleep, restingHeart, hrv])
    }

    func fetch(referenceDate: Date) async -> [TrackingCue] {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeart = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let calendar = Calendar.current
        let eventDay = calendar.startOfDay(for: referenceDate)
        let eventEnd = calendar.date(byAdding: .day, value: 1, to: eventDay) ?? referenceDate
        let baselineStart = calendar.date(byAdding: .day, value: -30, to: eventDay) ?? eventDay
        async let sleepSamples = samples(type: sleep, start: baselineStart, end: eventEnd)
        async let heartSamples = samples(type: restingHeart, start: baselineStart, end: eventEnd)
        async let hrvSamples = samples(type: hrv, start: baselineStart, end: eventEnd)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let sleeps = await sleepSamples.compactMap { $0 as? HKCategorySample }.filter { asleepValues.contains($0.value) }
        let hearts = await heartSamples.compactMap { $0 as? HKQuantitySample }
        let hrvs = await hrvSamples.compactMap { $0 as? HKQuantitySample }
        var cues: [TrackingCue] = []

        let eventSleep = sleeps.filter { $0.endDate >= eventDay && $0.endDate < eventEnd }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
        let baselineSleepGroups = Dictionary(grouping: sleeps.filter { $0.endDate < eventDay }) { calendar.startOfDay(for: $0.endDate) }
        let baselineSleep = baselineSleepGroups.values.map { night in night.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60 }
        if eventSleep > 0 {
            let baseline = baselineSleep.isEmpty ? nil : baselineSleep.reduce(0, +) / Double(baselineSleep.count)
            cues.append(.init(source: .healthSleep, observation: comparison(label: "事件前一晚睡眠", eventValue: eventSleep, baseline: baseline, unit: "分钟")))
        } else if let latest = baselineSleepGroups.max(by: { $0.key < $1.key }) {
            let latestMinutes = latest.value.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
            let baseline = baselineSleep.isEmpty ? nil : baselineSleep.reduce(0, +) / Double(baselineSleep.count)
            let date = latest.key.formatted(date: .abbreviated, time: .omitted)
            cues.append(.init(source: .healthSleep, observation: comparison(label: "事件前夜无记录；最近一晚睡眠（\(date)，仅供参考）", eventValue: latestMinutes, baseline: baseline, unit: "分钟")))
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let cue = quantityComparison(label: "事件日静息心率", samples: hearts, eventDay: eventDay, eventEnd: eventEnd, unit: bpm, suffix: "bpm") {
            cues.append(.init(source: .healthHeartRate, observation: cue))
        }
        let milliseconds = HKUnit.secondUnit(with: .milli)
        if let cue = quantityComparison(label: "事件日 HRV（SDNN）", samples: hrvs, eventDay: eventDay, eventEnd: eventEnd, unit: milliseconds, suffix: "ms") {
            cues.append(.init(source: .healthHRV, observation: cue))
        }
        return cues
    }

    private func samples(type: HKSampleType, start: Date, end: Date) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private func quantityComparison(label: String, samples: [HKQuantitySample], eventDay: Date, eventEnd: Date, unit: HKUnit, suffix: String) -> String? {
        let eventValues = samples.filter { $0.startDate >= eventDay && $0.startDate < eventEnd }.map { $0.quantity.doubleValue(for: unit) }
        guard !eventValues.isEmpty else { return nil }
        let baselineValues = samples.filter { $0.startDate < eventDay }.map { $0.quantity.doubleValue(for: unit) }
        let eventAverage = eventValues.reduce(0, +) / Double(eventValues.count)
        let baseline = baselineValues.isEmpty ? nil : baselineValues.reduce(0, +) / Double(baselineValues.count)
        return comparison(label: label, eventValue: eventAverage, baseline: baseline, unit: suffix)
    }

    private func comparison(label: String, eventValue: Double, baseline: Double?, unit: String) -> String {
        guard let baseline, baseline > 0 else { return "\(label)：\(Int(eventValue.rounded())) \(unit)；个人基线数据不足" }
        let percent = Int((((eventValue - baseline) / baseline) * 100).rounded())
        let direction = percent == 0 ? "接近" : (percent > 0 ? "高于" : "低于")
        return "\(label)：\(Int(eventValue.rounded())) \(unit)；\(direction)此前 30 天个人均值约 \(abs(percent))%（仅作线索）"
    }
}

actor CalendarService {
    private let store = EKEventStore()
    func requestAuthorization() async { _ = try? await store.requestFullAccessToEvents() }

    func fetch(referenceDate: Date) -> [TrackingCue] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? referenceDate
        let baselineStart = calendar.date(byAdding: .day, value: -28, to: day) ?? day
        let eventItems = store.events(matching: store.predicateForEvents(withStart: day, end: end, calendars: nil))
        let baselineItems = store.events(matching: store.predicateForEvents(withStart: baselineStart, end: day, calendars: nil))
        let eventHours = eventItems.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
        let baselineDailyHours = baselineItems.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600 / 28
        let difference = eventHours - baselineDailyHours
        let comparison = abs(difference) < 0.5 ? "接近平常" : (difference > 0 ? "高于平常约 \(String(format: "%.1f", difference)) 小时" : "低于平常约 \(String(format: "%.1f", abs(difference))) 小时")
        return [.init(source: .calendarLoad, observation: "事件日：\(eventItems.count) 个日程、约 \(String(format: "%.1f", eventHours)) 小时；\(comparison)（只统计时间，不读取内容）")]
    }
}
