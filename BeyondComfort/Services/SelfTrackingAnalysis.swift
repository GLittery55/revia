import Foundation

struct SelfTrackingAnalysisConfiguration: Equatable {
    var recentDays = 7
    var shortBaselineDays = 14
    var stableBaselineDays = 28
    var minimumBaselineCoverage = 0.5
}

/// Permission prompts are process-scoped, while computed cues belong to one reflection session.
/// Replacing a session must therefore trigger a fresh deterministic read even when authorization
/// has already been requested and an earlier session left a refresh timestamp behind.
struct TrackingRefreshPolicy {
    static func shouldRefresh(
        sessionCueCount: Int,
        refreshedAt: Date?
    ) -> Bool {
        sessionCueCount == 0 || refreshedAt == nil
    }
}

/// A presentation-level grouping used to select several independent background
/// cues. The domains deliberately describe data sources, not a psychological
/// interpretation of the user.
enum SelfTrackingDomain: String, Codable, CaseIterable {
    case sleep
    case schedule
    case activity
    case cardiovascular
    case deviceUse
    case environment

    var displayName: String {
        switch self {
        case .sleep: "睡眠"
        case .schedule: "日程"
        case .activity: "活动"
        case .cardiovascular: "心率相关记录"
        case .deviceUse: "设备使用"
        case .environment: "外部环境"
        }
    }
}

/// A deterministic, multi-domain selection that can be handed to a view model.
/// It carries its own epistemic boundary so callers do not need to invent a
/// causal or responsibility-based interpretation of several measurements.
struct SelfTrackingContextSummary: Equatable {
    let selectedInsights: [TrackingInsight]
    let representedDomains: [SelfTrackingDomain]
    let observations: [String]
    let limitations: [String]
    let boundaryStatement: String

    var promptText: String {
        let observationText = observations.map { "- \($0)" }.joined(separator: "\n")
        let limitationText = limitations.map { "- \($0)" }.joined(separator: "\n")
        return """
        可供用户判断是否相关的记录：
        \(observationText)
        限制：
        \(limitationText)
        \(boundaryStatement)
        """
    }
}

extension TrackingMetric {
    var isSleepNightMetric: Bool {
        switch self {
        case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity:
            true
        default:
            false
        }
    }

    var usesCircularClockComparison: Bool {
        self == .sleepTiming || self == .sleepWakeTime
    }

    var selfTrackingDomain: SelfTrackingDomain {
        switch self {
        case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity: .sleep
        case .calendarLoad: .schedule
        case .steps: .activity
        case .restingHeartRate, .heartRateVariability: .cardiovascular
        case .screenTime: .deviceUse
        case .weather: .environment
        }
    }
}

extension SelfTrackingAnalysis {
    /// Selects several cues using only measurement quality, baseline support,
    /// magnitude of recorded difference, and domain diversity. Conversation
    /// content, emotion, route, and model recommendations never affect ranking.
    func rankedBackgroundInsights(
        maximumCount: Int = 6,
        maximumPerDomain: Int = 2
    ) -> [TrackingInsight] {
        guard maximumCount > 0, maximumPerDomain > 0 else { return [] }

        let usable = insights
            .filter { $0.validSampleCount > 0 }
            .sorted(by: SelfTrackingInsightRanking.precedes)
        var selected: [TrackingInsight] = []
        var selectedIDs = Set<UUID>()
        var domainCounts: [SelfTrackingDomain: Int] = [:]

        // First pass favours breadth: one well-supported cue from each domain.
        for insight in usable where selected.count < maximumCount {
            let domain = insight.metric.selfTrackingDomain
            guard domainCounts[domain, default: 0] == 0 else { continue }
            selected.append(insight)
            selectedIDs.insert(insight.id)
            domainCounts[domain, default: 0] += 1
        }

        // A second pass may include another distinct measure such as sleep timing
        // or HRV, while still preventing one source family from taking over.
        for insight in usable where selected.count < maximumCount {
            guard !selectedIDs.contains(insight.id) else { continue }
            let domain = insight.metric.selfTrackingDomain
            guard domainCounts[domain, default: 0] < maximumPerDomain else { continue }
            selected.append(insight)
            selectedIDs.insert(insight.id)
            domainCounts[domain, default: 0] += 1
        }
        return selected
    }

    func backgroundContextSummary(
        maximumCount: Int = 6,
        maximumPerDomain: Int = 2
    ) -> SelfTrackingContextSummary {
        let selected = rankedBackgroundInsights(
            maximumCount: maximumCount,
            maximumPerDomain: maximumPerDomain
        )
        var domains: [SelfTrackingDomain] = []
        var limitations: [String] = []
        for insight in selected {
            let domain = insight.metric.selfTrackingDomain
            if !domains.contains(domain) { domains.append(domain) }
            for limitation in insight.limitations where !limitations.contains(limitation) {
                limitations.append(limitation)
            }
            if !insight.possibleConfounders.isEmpty {
                let measurementLimit = "\(domain.displayName)记录还可能受\(insight.possibleConfounders.prefix(3).joined(separator: "、"))等因素影响"
                if !limitations.contains(measurementLimit) {
                    limitations.append(measurementLimit)
                }
            }
        }
        let crossMetricLimitation = "不同指标的测量方式和记录完整性不同，不能合并成单一结论"
        if selected.count > 1, !limitations.contains(crossMetricLimitation) {
            limitations.append(crossMetricLimitation)
        }
        return SelfTrackingContextSummary(
            selectedInsights: selected,
            representedDomains: domains,
            observations: selected.map(\.neutralObservation),
            limitations: limitations,
            boundaryStatement: "这些数据只是不确定的情境线索，不能证明行为原因、心理状态或责任；是否与当时经历相关，需要由用户确认。"
        )
    }
}

extension Collection where Element == TrackingCue {
    /// Convenience for the current app boundary, where HealthKit and EventKit
    /// services expose cues rather than a shared dataset. Only cues backed by a
    /// valid deterministic insight participate in ranking.
    func rankedBackgroundCues(
        maximumCount: Int = 6,
        maximumPerDomain: Int = 2
    ) -> [TrackingCue] {
        let cues = Array(self)
        let analysis = SelfTrackingAnalysis(
            insights: cues.compactMap(\.insight),
            patternCandidates: []
        )
        let rankedInsightIDs = analysis.rankedBackgroundInsights(
            maximumCount: maximumCount,
            maximumPerDomain: maximumPerDomain
        ).map(\.id)
        return rankedInsightIDs.compactMap { insightID in
            cues.first { $0.insight?.id == insightID }
        }
    }

    func backgroundContextSummary(
        maximumCount: Int = 6,
        maximumPerDomain: Int = 2
    ) -> SelfTrackingContextSummary {
        SelfTrackingAnalysis(
            insights: compactMap(\.insight),
            patternCandidates: []
        ).backgroundContextSummary(
            maximumCount: maximumCount,
            maximumPerDomain: maximumPerDomain
        )
    }
}

private enum SelfTrackingInsightRanking {
    static func precedes(_ lhs: TrackingInsight, _ rhs: TrackingInsight) -> Bool {
        let lhsKey = key(for: lhs)
        let rhsKey = key(for: rhs)
        if lhsKey != rhsKey { return lhsKey.lexicographicallyPrecedes(rhsKey) }
        return metricOrder(lhs.metric) < metricOrder(rhs.metric)
    }

    /// Lower tuple components are ranked first. The effect component is capped
    /// so a large but poorly supported number cannot dominate data quality.
    private static func key(for insight: TrackingInsight) -> [Double] {
        let strength: Double = switch insight.strength {
        case .persistentPattern: 0
        case .baselineComparison: 1
        case .descriptiveOnly: 2
        }
        let confidence: Double = switch insight.confidence {
        case .high: 0
        case .moderate: 1
        case .low: 2
        }
        let coverage = Double(insight.validSampleCount) /
            Double(max(insight.expectedSampleCount, 1))
        let effect = min(abs(insight.relativeDifference ?? 0), 2)
        return [strength, confidence, -coverage, -effect]
    }

    private static func metricOrder(_ metric: TrackingMetric) -> Int {
        switch metric {
        case .sleepDuration: 0
        case .sleepTiming: 1
        case .sleepWakeTime: 2
        case .sleepContinuity: 3
        case .calendarLoad: 4
        case .steps: 5
        case .restingHeartRate: 6
        case .heartRateVariability: 7
        case .screenTime: 8
        case .weather: 9
        }
    }
}

protocol SelfTrackingAnalyzing: Sendable {
    func analyze(
        eventDate: Date?,
        availableData: SelfTrackingDataset
    ) async throws -> SelfTrackingAnalysis
}

protocol ContextualLoadInferring: Sendable {
    func infer(from analysis: SelfTrackingAnalysis) -> ContextualLoadInference
}

/// Converts several independently computed context signals into one deliberately coarse
/// hypothesis. Health signals use personal-baseline differences. Calendar is different: it is a
/// direct external record, so its recent event count and occupied time are used without comparing
/// them with a personal "normal" schedule. Even then, the inference says only that time was
/// scheduled; it never upgrades that fact to "the person is busy". Activity is retained only as
/// an alternative explanation because step count alone does not identify strain, energy, or
/// emotion.
struct DeterministicContextualLoadInferer: ContextualLoadInferring {
    func infer(from analysis: SelfTrackingAnalysis) -> ContextualLoadInference {
        let comparable = analysis.insights.filter(isReliableBaselineComparison)
        let reliableRecent = analysis.insights.filter(isReliableRecentObservation)
        let shorterSleep = comparable.first {
            $0.metric == .sleepDuration && ($0.absoluteDifference ?? 0) <= -0.75
        }
        // A stable personal baseline is not an adequacy judgment. Regularly sleeping less than
        // seven hours can remain useful lived context even when there is no recent deviation.
        let persistentlyShortSleep = reliableRecent.first {
            $0.metric == .sleepDuration && ($0.recentMedian ?? .greatestFiniteMagnitude) < 7
        }
        let sleepDurationContext = shorterSleep ?? persistentlyShortSleep
        let lessContinuousSleep = comparable.first {
            $0.metric == .sleepContinuity && ($0.absoluteDifference ?? 0) <= -0.10
        }
        let lateSleepTiming = reliableRecent.first {
            guard $0.metric == .sleepTiming,
                  let recent = $0.recentMedian else { return false }
            let laterThanPersonalBaseline = ($0.absoluteDifference ?? 0) >= 0.75
            let recordedInEarlyMorning = recent >= 0.5 && recent <= 5
            return laterThanPersonalBaseline || recordedInEarlyMorning
        }
        let reducedActivity = comparable.first {
            $0.metric == .steps && ($0.relativeDifference ?? 0) <= -0.20
        }
        let higherRestingHeartRate = comparable.first {
            guard $0.metric == .restingHeartRate,
                  let difference = $0.absoluteDifference,
                  let baseline = $0.baselineMedian,
                  baseline > 0 else { return false }
            return difference >= max(5, baseline * 0.07)
        }
        let lowerHeartRateVariability = comparable.first {
            guard $0.metric == .heartRateVariability,
                  let difference = $0.absoluteDifference,
                  let relativeDifference = $0.relativeDifference else { return false }
            return difference <= -5 && relativeDifference <= -0.15
        }
        let recordedSchedule = analysis.insights.first(where: isUsableRecordedSchedule)

        let sleepSignals = uniqueInsights([sleepDurationContext, lessContinuousSleep])
        let cardiovascularSignals = [
            higherRestingHeartRate,
            lowerHeartRateVariability,
        ].compactMap { $0 }
        let visibleContext = uniqueInsights([
            sleepDurationContext,
            recordedSchedule,
            lateSleepTiming,
            reducedActivity,
        ])
        let dialogueHypothesis = makeDialogueHypothesis(
            from: visibleContext,
            maximumCueCount: 2
        )

        if !sleepSignals.isEmpty, !cardiovascularSignals.isEmpty {
            let physiologicalSignals = sleepSignals + cardiovascularSignals
            let supporting = uniqueInsights(
                physiologicalSignals.map(Optional.some) + visibleContext.map(Optional.some)
            )
            let hasStrongAgreement =
                physiologicalSignals.count >= 3 &&
                physiologicalSignals.allSatisfy {
                    $0.confidence == .high && $0.strength == .persistentPattern
                }
            return makeInference(
                state: hasStrongAgreement ? .elevated : .possiblyElevated,
                confidence: hasStrongAgreement ? .high : .moderate,
                activation: .possiblyElevated,
                energy: .possiblyReduced,
                supporting: supporting,
                alternatives: alternativeExplanations(
                    from: comparable,
                    supporting: supporting
                ),
                dialogueHypothesis: dialogueHypothesis
            )
        }

        if !sleepSignals.isEmpty {
            let supporting = uniqueInsights(
                sleepSignals.map(Optional.some) + visibleContext.map(Optional.some)
            )
            return makeInference(
                state: .possibleReducedRecovery,
                confidence: .moderate,
                activation: .unknown,
                energy: .possiblyReduced,
                supporting: supporting,
                alternatives: alternativeExplanations(
                    from: comparable,
                    supporting: supporting
                ),
                dialogueHypothesis: dialogueHypothesis
            )
        }

        if let recordedSchedule {
            let supporting = uniqueInsights(
                [Optional(recordedSchedule), lateSleepTiming, reducedActivity]
            )
            return makeInference(
                state: .recordedScheduleContext,
                confidence: .moderate,
                activation: .unknown,
                energy: .unknown,
                supporting: supporting,
                alternatives: alternativeExplanations(
                    from: comparable,
                    supporting: supporting
                ),
                dialogueHypothesis: makeDialogueHypothesis(
                    from: supporting,
                    maximumCueCount: 2
                )
            )
        }

        // A factual late-sleep or reduced-activity pattern may still be worth one restrained
        // contextual reveal even when the coarse load state is unchanged. It is never promoted to
        // fatigue, pressure, emotion, cause, responsibility, or a workflow precondition.
        let descriptiveContext = uniqueInsights([lateSleepTiming, reducedActivity])
        if let dialogueHypothesis = makeDialogueHypothesis(
            from: descriptiveContext,
            maximumCueCount: 2
        ) {
            return makeInference(
                state: .usualRange,
                confidence: .moderate,
                activation: .unknown,
                energy: .unknown,
                supporting: descriptiveContext,
                alternatives: alternativeExplanations(
                    from: comparable,
                    supporting: descriptiveContext
                ),
                dialogueHypothesis: dialogueHypothesis
            )
        }

        let state: ContextualLoadState = comparable.isEmpty
            ? .insufficientEvidence
            : .usualRange
        return makeInference(
            state: state,
            confidence: .low,
            activation: .unknown,
            energy: .unknown,
            supporting: [],
            alternatives: alternativeExplanations(from: comparable, supporting: []),
            dialogueHypothesis: nil
        )
    }

    private func isReliableBaselineComparison(_ insight: TrackingInsight) -> Bool {
        guard insight.metric != .calendarLoad,
              insight.strength != .descriptiveOnly,
              insight.confidence != .low,
              insight.recentMedian != nil,
              insight.baselineMedian != nil,
              insight.absoluteDifference != nil else {
            return false
        }
        return insight.validSampleCount >= 4
    }

    private func isReliableRecentObservation(_ insight: TrackingInsight) -> Bool {
        insight.confidence != .low
            && insight.validSampleCount >= 4
            && insight.recentMedian != nil
    }

    private func uniqueInsights(_ values: [TrackingInsight?]) -> [TrackingInsight] {
        var seen = Set<UUID>()
        return values.compactMap { insight in
            guard let insight, seen.insert(insight.id).inserted else { return nil }
            return insight
        }
    }

    /// Produces only concrete, ordinary-life context. HRV and resting heart rate may strengthen
    /// confidence internally, but are intentionally absent from visible wording because they do
    /// not translate into one specific lived or psychological state.
    private func makeDialogueHypothesis(
        from insights: [TrackingInsight],
        maximumCueCount: Int
    ) -> String? {
        guard maximumCueCount > 0 else { return nil }
        var clauses: [String] = []
        for insight in insights {
            let clause: String?
            switch insight.metric {
            case .sleepDuration:
                if let recent = insight.recentMedian, recent < 7 {
                    clause = "睡得不多"
                } else if (insight.absoluteDifference ?? 0) < 0 {
                    clause = "睡得比平时少一些"
                } else {
                    clause = nil
                }
            case .sleepTiming:
                if let recent = insight.recentMedian, recent >= 0.5 && recent <= 5 {
                    clause = "多在凌晨入睡"
                } else {
                    clause = "入睡比平时晚一些"
                }
            case .calendarLoad:
                clause = "日程里排着一些事情"
            case .steps:
                clause = "走动比平时少一些"
            case .sleepWakeTime, .sleepContinuity, .restingHeartRate,
                 .heartRateVariability, .screenTime, .weather:
                clause = nil
            }
            if let clause, !clauses.contains(clause) {
                clauses.append(clause)
            }
            if clauses.count == maximumCueCount { break }
        }
        guard !clauses.isEmpty else { return nil }
        return "用户最近几天" + clauses.joined(separator: "，而且") + "。"
    }

    private func isUsableRecordedSchedule(_ insight: TrackingInsight) -> Bool {
        guard insight.metric == .calendarLoad,
              insight.validSampleCount >= 4,
              let occupiedHours = insight.recentTotal,
              let eventCount = insight.recentRecordCount else {
            return false
        }
        return occupiedHours > 0 && eventCount > 0
    }

    private func alternativeExplanations(
        from insights: [TrackingInsight],
        supporting: [TrackingInsight]
    ) -> [String] {
        let supportingMetrics = Set(supporting.map(\.metric))
        var alternatives: [String] = []
        if supportingMetrics.contains(.calendarLoad) {
            alternatives.append("未写入日历的任务，以及日程是否按原计划发生")
        }
        if supportingMetrics.contains(where: {
            $0.selfTrackingDomain == .sleep || $0.selfTrackingDomain == .cardiovascular
        }) {
            alternatives.append(contentsOf: [
                "近期运动、体力活动或恢复过程",
                "身体不适、咖啡因、酒精、药物或临时作息变化",
                "设备佩戴、测量时段或同步差异",
            ])
        }
        if let steps = insights.first(where: { $0.metric == .steps }),
           let relativeDifference = steps.relativeDifference {
            if relativeDifference >= 0.20 {
                alternatives.insert("近期活动量增加带来的身体负荷", at: 0)
            } else if relativeDifference <= -0.20 {
                alternatives.insert("日常活动节奏变化或设备未随身携带", at: 0)
            }
        }
        return alternatives
    }

    private func makeInference(
        state: ContextualLoadState,
        confidence: ContextualLoadConfidence,
        activation: ContextualActivationState,
        energy: ContextualEnergyState,
        supporting: [TrackingInsight],
        alternatives: [String],
        dialogueHypothesis: String?
    ) -> ContextualLoadInference {
        let start = supporting.map(\.observationWindow.start).min()
        let end = supporting.map(\.observationWindow.end).max()
        let window = start.flatMap { start in
            end.map { DateInterval(start: start, end: $0) }
        }
        return ContextualLoadInference(
            state: state,
            confidence: confidence,
            activation: activation,
            energy: energy,
            observationWindow: window,
            supportingInsightIDs: supporting.map(\.id),
            supportingMetrics: supporting.map(\.metric),
            alternativeExplanations: alternatives,
            dialogueHypothesis: dialogueHypothesis,
            relevance: .notReviewed
        )
    }
}

/// Computes occupied calendar time as a union of intervals so simultaneous events are counted
/// once. Only the clipped duration inside the requested day contributes to the total.
struct CalendarOccupiedTimeCalculator {
    private static func clippedAndMerged(
        intervals: [DateInterval],
        within window: DateInterval
    ) -> [DateInterval] {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end < rhs.end
        }
        guard let first = clipped.first else { return [] }
        var merged = [first]
        for interval in clipped.dropFirst() {
            guard let last = merged.last else { continue }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func occupiedHours(
        intervals: [DateInterval],
        within window: DateInterval
    ) -> Double {
        clippedAndMerged(intervals: intervals, within: window)
            .reduce(0) { $0 + $1.duration } / 3_600
    }

    static func longestFreeBlockMinutes(
        intervals: [DateInterval],
        within window: DateInterval
    ) -> Double {
        let occupied = clippedAndMerged(intervals: intervals, within: window)
        guard !occupied.isEmpty else { return window.duration / 60 }
        var longest = max(occupied[0].start.timeIntervalSince(window.start), 0)
        for pair in zip(occupied, occupied.dropFirst()) {
            longest = max(longest, pair.1.start.timeIntervalSince(pair.0.end))
        }
        if let last = occupied.last {
            longest = max(longest, window.end.timeIntervalSince(last.end))
        }
        return longest / 60
    }

    static func backToBackPairCount(
        intervals: [DateInterval],
        within window: DateInterval,
        maximumGap: TimeInterval = 300
    ) -> Int {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
        return zip(clipped, clipped.dropFirst()).reduce(0) { count, pair in
            let gap = pair.1.start.timeIntervalSince(pair.0.end)
            return count + ((0...maximumGap).contains(gap) ? 1 : 0)
        }
    }
}

extension SelfTrackingAnalysis {
    func contextualLoadInference(
        using inferer: any ContextualLoadInferring = DeterministicContextualLoadInferer()
    ) -> ContextualLoadInference {
        inferer.infer(from: self)
    }
}

struct DeterministicSelfTrackingAnalyzer: SelfTrackingAnalyzing {
    let configuration: SelfTrackingAnalysisConfiguration
    let calendar: Calendar

    init(
        configuration: SelfTrackingAnalysisConfiguration = .init(),
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    func analyze(
        eventDate: Date?,
        availableData: SelfTrackingDataset
    ) async throws -> SelfTrackingAnalysis {
        let reference = calendar.startOfDay(for: eventDate ?? .now)
        var insights: [TrackingInsight] = []
        for metric in TrackingMetric.allCases {
            guard let points = availableData.dailyMetrics[metric], !points.isEmpty else { continue }
            insights.append(makeInsight(
                metric: metric,
                points: normalizedDailyPoints(points, metric: metric),
                provenance: availableData.provenance[metric] ?? [],
                referenceDate: reference
            ))
        }
        return SelfTrackingAnalysis(
            insights: insights,
            patternCandidates: patternCandidates(from: insights)
        )
    }

    private func makeInsight(
        metric: TrackingMetric,
        points: [TrackingDataPoint],
        provenance: [TrackingProvenance],
        referenceDate: Date
    ) -> TrackingInsight {
        let recentStart = calendar.date(
            byAdding: .day,
            value: -(configuration.recentDays - 1),
            to: referenceDate
        ) ?? referenceDate
        let recentEnd = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        let baselineEnd = recentStart
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -configuration.stableBaselineDays,
            to: baselineEnd
        ) ?? baselineEnd

        let recentPoints = points.filter { $0.date >= recentStart && $0.date < recentEnd }
        let baselinePoints = points.filter { $0.date >= baselineStart && $0.date < baselineEnd }
        let recentValues = recentPoints.compactMap(\.value)
        let recentTotal = metric == .calendarLoad ? recentValues.reduce(0, +) : nil
        let recentRecordCount = metric == .calendarLoad
            ? recentPoints.reduce(0) { partial, point in
                guard point.value != nil else { return partial }
                return partial + max(point.count, 0)
            }
            : nil
        let baselineValues = baselinePoints.compactMap(\.value)
        let recentMedian = metricMedian(metric, values: recentValues)
        let recentIQR = metricSpread(metric, values: recentValues, center: recentMedian)
        let baselineMedian = metricMedian(metric, values: baselineValues)
        let baselineCoverage = Double(baselineValues.count) /
            Double(max(configuration.stableBaselineDays, 1))
        let supportsBaseline = baselineValues.count >= configuration.shortBaselineDays &&
            baselineCoverage >= configuration.minimumBaselineCoverage
        let absoluteDifference = supportsBaseline
            ? difference(recentMedian, baselineMedian, metric: metric)
            : nil
        let relativeDifference: Double? = {
            guard !metric.usesCircularClockComparison else { return nil }
            guard let absoluteDifference, let baselineMedian, baselineMedian != 0 else { return nil }
            return absoluteDifference / abs(baselineMedian)
        }()
        let mad = supportsBaseline
            ? metricMedianAbsoluteDeviation(metric, values: baselineValues, center: baselineMedian)
            : nil
        let iqr = supportsBaseline
            ? metricSpread(metric, values: baselineValues, center: baselineMedian)
            : nil
        let longestRun = TrackingStatistics.longestConsecutiveRun(
            points: recentPoints,
            calendar: calendar
        )
        let persistent = supportsBaseline && isPersistent(
            metric: metric,
            recentValues: recentValues,
            baselineMedian: baselineMedian,
            mad: mad
        )
        let strength: TrackingInsightStrength = persistent
            ? .persistentPattern
            : (supportsBaseline ? .baselineComparison : .descriptiveOnly)
        let coverage = Double(recentValues.count) / Double(max(configuration.recentDays, 1))
        let confidence: TrackingInsightConfidence = {
            if coverage >= 0.85 && supportsBaseline { return .high }
            if coverage >= 0.55 { return .moderate }
            return .low
        }()
        let missing = max(configuration.recentDays - recentValues.count, 0)
        var limitations: [String] = []
        if missing > 0 { limitations.append("最近窗口缺少 \(missing) 天记录") }
        if !supportsBaseline { limitations.append("个人历史覆盖不足，不能进行可靠的基线比较") }
        if provenance.isEmpty { limitations.append("数据来源元信息不完整") }

        var insight = TrackingInsight(
            id: UUID(),
            metric: metric,
            observationWindow: DateInterval(start: recentStart, end: recentEnd),
            validSampleCount: recentValues.count,
            expectedSampleCount: configuration.recentDays,
            coverageDescription: "\(recentValues.count)/\(configuration.recentDays) \(metric.isSleepNightMetric ? "晚" : "天")有记录",
            neutralObservation: neutralObservation(
                metric: metric,
                validDays: recentValues.count,
                expectedDays: configuration.recentDays,
                recentMedian: recentMedian,
                baselineMedian: supportsBaseline ? baselineMedian : nil,
                difference: absoluteDifference,
                recentIQR: recentIQR,
                recentTotal: recentTotal,
                recentRecordCount: recentRecordCount
            ),
            baselineWindow: supportsBaseline ? DateInterval(start: baselineStart, end: baselineEnd) : nil,
            baselineDescription: supportsBaseline
                ? "过去 \(configuration.stableBaselineDays) 天中有 \(baselineValues.count) 天可用于个人基线"
                : nil,
            absoluteDifference: absoluteDifference,
            relativeDifference: relativeDifference,
            strength: strength,
            confidence: confidence,
            limitations: limitations,
            possibleConfounders: confounders(for: metric),
            suggestedReflectionQuestion: reflectionQuestion(for: metric),
            provenance: provenance,
            recentMedian: recentMedian,
            recentTotal: recentTotal,
            recentRecordCount: recentRecordCount,
            baselineMedian: supportsBaseline ? baselineMedian : nil,
            medianAbsoluteDeviation: mad,
            interquartileRange: iqr,
            longestConsecutiveRun: longestRun,
            userRelevance: .notReviewed
        )
        insight.recentDailyPoints = recentPoints
        // Current-v5 exposes the observed baseline and its coverage as facts. It does not use
        // Swift's `supportsBaseline` decision to hide the value or label its quality.
        insight.factualBaselineMedian = baselineMedian
        insight.baselineObservedDays = baselineValues.count
        insight.baselineExpectedDays = configuration.stableBaselineDays
        return insight
    }

    private func difference(
        _ lhs: Double?,
        _ rhs: Double?,
        metric: TrackingMetric
    ) -> Double? {
        guard let lhs, let rhs else { return nil }
        var result = lhs - rhs
        if metric.usesCircularClockComparison {
            while result > 12 { result -= 24 }
            while result <= -12 { result += 24 }
        }
        return result
    }

    private func normalizedDailyPoints(
        _ points: [TrackingDataPoint],
        metric: TrackingMetric
    ) -> [TrackingDataPoint] {
        let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            let records = grouped[day] ?? []
            let values = records.compactMap { cleanedValue($0.value, metric: metric) }
            return TrackingDataPoint(
                date: day,
                value: metricMedian(metric, values: values),
                count: records.reduce(0) { $0 + max($1.count, 0) }
            )
        }
    }

    private func cleanedValue(_ value: Double?, metric: TrackingMetric) -> Double? {
        guard let value, value.isFinite else { return nil }
        switch metric {
        case .sleepDuration:
            return (0...24).contains(value) ? value : nil
        case .sleepTiming, .sleepWakeTime:
            return ((value.truncatingRemainder(dividingBy: 24)) + 24)
                .truncatingRemainder(dividingBy: 24)
        case .sleepContinuity:
            return (0...1).contains(value) ? value : nil
        case .restingHeartRate:
            return value > 0 ? value : nil
        case .heartRateVariability, .steps, .calendarLoad, .screenTime:
            return value >= 0 ? value : nil
        case .weather:
            return value
        }
    }

    private func metricMedian(_ metric: TrackingMetric, values: [Double]) -> Double? {
        guard metric.usesCircularClockComparison else { return TrackingStatistics.median(values) }
        return TrackingStatistics.circularMedianHour(values)
    }

    private func metricSpread(
        _ metric: TrackingMetric,
        values: [Double],
        center: Double?
    ) -> Double? {
        guard metric.usesCircularClockComparison else {
            return TrackingStatistics.interquartileRange(values)
        }
        guard let center else { return nil }
        let unwrapped = values.map { center + TrackingStatistics.circularHourDifference($0, center) }
        return TrackingStatistics.interquartileRange(unwrapped)
    }

    private func metricMedianAbsoluteDeviation(
        _ metric: TrackingMetric,
        values: [Double],
        center: Double?
    ) -> Double? {
        guard metric.usesCircularClockComparison else {
            return TrackingStatistics.medianAbsoluteDeviation(values)
        }
        guard let center else { return nil }
        return TrackingStatistics.median(values.map {
            abs(TrackingStatistics.circularHourDifference($0, center))
        })
    }

    private func isPersistent(
        metric: TrackingMetric,
        recentValues: [Double],
        baselineMedian: Double?,
        mad: Double?
    ) -> Bool {
        guard recentValues.count >= 3, let baselineMedian else { return false }
        let threshold = max(mad ?? 0, metric.usesCircularClockComparison ? 0.25 : abs(baselineMedian) * 0.03)
        let last = Array(recentValues.suffix(3))
        let differences = last.compactMap { difference($0, baselineMedian, metric: metric) }
        return differences.allSatisfy { $0 > threshold } ||
            differences.allSatisfy { $0 < -threshold }
    }

    private func neutralObservation(
        metric: TrackingMetric,
        validDays: Int,
        expectedDays: Int,
        recentMedian: Double?,
        baselineMedian: Double?,
        difference: Double?,
        recentIQR: Double?,
        recentTotal: Double?,
        recentRecordCount: Int?
    ) -> String {
        let noun = metric.isSleepNightMetric ? "晚" : "天"
        guard let recentMedian else {
            return "最近 \(expectedDays) 天没有可用于这项描述的记录。"
        }
        if metric == .sleepTiming {
            let regularity = recentIQR.map {
                "有记录夜晚的入睡时间四分位范围约为 \(String(format: "%.1f", $0)) 小时"
            } ?? "目前记录还不足以稳定描述入睡时间的规律"
            guard let baselineMedian, let difference else {
                return "最近 \(expectedDays) 天中有 \(validDays) 晚可用于入睡时间描述；入睡时间中位数约为 \(clockTime(recentMedian))，\(regularity)。个人历史覆盖不足，这只能作为背景。"
            }
            let minutes = Int((abs(difference) * 60).rounded())
            let direction = difference >= 0 ? "更晚" : "更早"
            return "最近入睡时间中位数约为 \(clockTime(recentMedian))，个人基线约为 \(clockTime(baselineMedian))，相差约 \(minutes) 分钟（\(direction)）；\(regularity)。这只是记录差异，不能说明原因或责任。"
        }
        if metric == .sleepWakeTime {
            guard let baselineMedian, let difference else {
                return "最近 \(expectedDays) 天中有 \(validDays) 晚可用于醒来时间描述；醒来时间中位数约为 \(clockTime(recentMedian))。个人历史覆盖不足，这只能作为背景。"
            }
            let minutes = Int((abs(difference) * 60).rounded())
            let direction = difference >= 0 ? "更晚" : "更早"
            return "最近醒来时间中位数约为 \(clockTime(recentMedian))，个人基线约为 \(clockTime(baselineMedian))，相差约 \(minutes) 分钟（\(direction)）。这只是记录差异，不能说明原因或责任。"
        }
        if metric == .calendarLoad {
            let hours = recentTotal ?? 0
            let eventCount = recentRecordCount ?? 0
            guard eventCount > 0, hours > 0 else {
                return "最近 \(expectedDays) 天日历中没有记录到占用时间的定时日程；这不能说明现实中没有其他任务、原因或责任。"
            }
            return "最近 \(expectedDays) 天日历中记录到 \(eventCount) 个定时日程，去重后合计占用约 \(formatted(hours, metric: metric))；不读取标题或内容，未写入日历的任务也不在其中，不能说明现实中的总工作量、原因或责任。"
        }
        guard let baselineMedian, let difference else {
            if metric == .sleepContinuity {
                return "最近 \(expectedDays) 天中有 \(validDays) 晚可用于已记录睡眠区间的连续程度描述；中位数约为 \(formatted(recentMedian, metric: metric))。个人历史覆盖不足，它不等同于主观睡眠质量，只能作为背景。"
            }
            return "最近 \(expectedDays) 天中有 \(validDays) \(noun)记录，中位数约为 \(formatted(recentMedian, metric: metric))；个人历史覆盖不足，只能作为背景，不能说明原因或责任。"
        }
        switch metric {
        case .sleepDuration:
            let minutes = Int((difference * 60).rounded())
            let direction = minutes >= 0 ? "更多" : "更少"
            return "最近睡眠时长中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，相差约 \(abs(minutes)) 分钟（\(direction)）；这只是记录差异，不能说明原因或责任。"
        case .sleepContinuity:
            let points = Int((recentMedian * 100).rounded())
            let baselinePoints = Int((baselineMedian * 100).rounded())
            let change = Int((abs(difference) * 100).rounded())
            let direction = difference >= 0 ? "更高" : "更低"
            return "最近已记录睡眠区间的连续程度中位数约为 \(points)%，个人基线约为 \(baselinePoints)%，相差约 \(change) 个百分点（\(direction)）。它只反映设备记录区间的连续程度，不等同于主观睡眠质量，也不能说明原因或责任。"
        case .restingHeartRate:
            let direction = difference >= 0 ? "较高" : "较低"
            return "最近静息心率中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，相差约 \(String(format: "%.1f", abs(difference))) bpm（\(direction)）；记录不能说明原因、心理状态或责任。"
        case .heartRateVariability:
            let direction = difference >= 0 ? "较高" : "较低"
            return "最近 HRV（SDNN）中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，相差约 \(String(format: "%.1f", abs(difference))) ms（\(direction)）；这不是心理压力或责任的直接测量。"
        case .steps:
            let direction = difference >= 0 ? "更多" : "更少"
            return "最近每日步数中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，相差约 \(formatted(abs(difference), metric: metric))（\(direction)）；这里只描述设备记录到的活动，不能说明原因或责任。"
        case .calendarLoad:
            return "最近日历中记录到占用时间的定时日程；未写入日历的任务不在其中。"
        case .sleepTiming, .sleepWakeTime:
            return "最近睡眠时间与个人近期作息存在差异；仍需结合缺失记录理解。"
        case .screenTime:
            let minutes = Int((abs(difference) * 60).rounded())
            let direction = difference >= 0 ? "更多" : "更少"
            return "最近每日屏幕使用中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，相差约 \(minutes) 分钟（\(direction)）；用途无法从时长判断，也不能证明回避或责任。"
        case .weather:
            return "最近天气指标中位数约为 \(formatted(recentMedian, metric: metric))，个人基线约为 \(formatted(baselineMedian, metric: metric))，差异约为 \(formatted(abs(difference), metric: metric))；它只能作为外部背景，不能说明行为原因或责任。"
        }
    }

    private func formatted(_ value: Double, metric: TrackingMetric) -> String {
        switch metric {
        case .sleepDuration, .calendarLoad, .screenTime:
            return "\(String(format: "%.1f", value)) 小时"
        case .sleepTiming, .sleepWakeTime:
            return clockTime(value)
        case .sleepContinuity:
            return "\(Int((value * 100).rounded()))%"
        case .restingHeartRate:
            return "\(String(format: "%.1f", value)) bpm"
        case .heartRateVariability:
            return "\(String(format: "%.1f", value)) ms"
        case .steps:
            return "\(Int(value.rounded())) 步"
        case .weather:
            return String(format: "%.1f", value)
        }
    }

    private func clockTime(_ decimalHour: Double) -> String {
        let normalized = ((decimalHour.truncatingRemainder(dividingBy: 24)) + 24)
            .truncatingRemainder(dividingBy: 24)
        let totalMinutes = Int((normalized * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func confounders(for metric: TrackingMetric) -> [String] {
        switch metric {
        case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity:
            return ["设备佩戴或同步情况", "设备记录的睡眠区间与主观感受不完全相同", "临时日程变化"]
        case .restingHeartRate, .heartRateVariability:
            return ["睡眠", "身体活动", "咖啡因", "身体状况", "测量设备与时段"]
        case .steps:
            return ["设备是否随身携带", "室内活动", "出行方式", "天气"]
        case .calendarLoad:
            return ["未写入日历的任务", "事件实际持续时间", "全天事件含义"]
        case .screenTime:
            return ["工作用途", "导航或沟通用途", "跨设备记录完整性"]
        case .weather:
            return ["室内安排", "交通方式", "用户自己的天气体验"]
        }
    }

    private func reflectionQuestion(for metric: TrackingMetric) -> String {
        return switch metric {
        case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity:
            "这些睡眠作息和记录连续性的背景，在那段经历里实际参与了哪一部分？"
        case .restingHeartRate, .heartRateVariability: "这段身体记录值得放进来一起看吗，也可以说不相关。"
        case .steps: "记录到的活动变化，在那几天的日常节奏里具体对应了什么？"
        case .calendarLoad: "那几天的安排有没有挤压你原本可用的时间？也可能没有。"
        case .screenTime: "这些使用时段在你记得的日常里主要对应了什么？"
        case .weather: "天气有没有实际改变出行或原本的日常安排？"
        }
    }

    private func patternCandidates(from insights: [TrackingInsight]) -> [PatternCandidate] {
        let pairs: [(TrackingMetric, TrackingMetric, [String])] = [
            (.sleepDuration, .calendarLoad, ["未记录的任务或照护安排", "设备同步与佩戴差异", "偶然的日程变化"]),
            (.steps, .restingHeartRate, ["设备是否随身携带", "身体活动类型", "测量设备与时段", "身体状况"]),
            (.steps, .heartRateVariability, ["设备是否随身携带", "身体活动类型", "测量设备与时段", "睡眠与身体状况"]),
        ]
        return pairs.compactMap { firstMetric, secondMetric, alternatives in
            guard let first = insights.first(where: { $0.metric == firstMetric && $0.validSampleCount > 0 }),
                  let second = insights.first(where: { $0.metric == secondMetric && $0.validSampleCount > 0 }) else {
                return nil
            }
            return PatternCandidate(
                id: UUID(),
                observedFeatures: [first.neutralObservation, second.neutralObservation],
                observationWindows: [first.observationWindow, second.observationWindow],
                coverage: [first.coverageDescription, second.coverageDescription],
                limitations: Array(Set(first.limitations + second.limitations)).sorted(),
                alternativeExplanations: alternatives,
                suggestedReflectionQuestion: "这两项记录在相近时间出现，但不能说明彼此因果。把它们并列作为背景时，你记得它们分别对应了什么？"
            )
        }
    }
}

enum TrackingStatistics {
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        return median(values.map { abs($0 - center) })
    }

    static func interquartileRange(_ values: [Double]) -> Double? {
        guard values.count >= 4 else { return nil }
        let sorted = values.sorted()
        let lower = Array(sorted.prefix(sorted.count / 2))
        let upper = Array(sorted.suffix(sorted.count / 2))
        guard let q1 = median(lower), let q3 = median(upper) else { return nil }
        return q3 - q1
    }

    static func circularHourDifference(_ lhs: Double, _ rhs: Double) -> Double {
        var result = lhs - rhs
        while result > 12 { result -= 24 }
        while result <= -12 { result += 24 }
        return result
    }

    /// A deterministic circular medoid avoids treating 23:30 and 00:30 as 23
    /// hours apart. For time-of-day tracking a medoid is more stable than a
    /// linear median across midnight and always remains an observed clock time.
    static func circularMedianHour(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let normalized = values.map {
            (($0.truncatingRemainder(dividingBy: 24)) + 24)
                .truncatingRemainder(dividingBy: 24)
        }
        return normalized.min { lhs, rhs in
            let lhsDistance = normalized.reduce(0) { $0 + abs(circularHourDifference($1, lhs)) }
            let rhsDistance = normalized.reduce(0) { $0 + abs(circularHourDifference($1, rhs)) }
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs < rhs
        }
    }

    static func longestConsecutiveRun(
        points: [TrackingDataPoint],
        calendar: Calendar
    ) -> Int {
        let validDays = points.filter { $0.value != nil }.map { calendar.startOfDay(for: $0.date) }.sorted()
        guard !validDays.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for pair in zip(validDays, validDays.dropFirst()) {
            if calendar.dateComponents([.day], from: pair.0, to: pair.1).day == 1 {
                current += 1
                longest = max(longest, current)
            } else if pair.0 != pair.1 {
                current = 1
            }
        }
        return longest
    }
}
