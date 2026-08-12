import Foundation

extension TurnReflectionAction {
    /// Current-v5 uses the existing action catalogue as deterministic field ownership. These
    /// properties do not add protocol state and are not shared with the legacy controller.
    var isCurrentV5TenderAction: Bool {
        switch self {
        case .distinguishFactFromPrediction,
             .softenGlobalSelfJudgment:
            return true
        case .acknowledgeExperience,
             .connectCommonHumanity,
             .acknowledgeBehaviorImpact,
             .clarifyBoundaryOrNeed,
             .identifyRepairDirection,
             .identifyProtectionDirection,
             .identifyChangeDirection,
             .synthesizeUnderstanding:
            return false
        }
    }

    var currentV5ProvidesTenderDistinction: Bool {
        self == .distinguishFactFromPrediction || self == .softenGlobalSelfJudgment
    }

    /// These existing actions name the question Fierce reflection is opening. They are not proof
    /// that the person has already formed a boundary, need, responsibility, or change direction.
    var isCurrentV5FierceInquiryAction: Bool {
        switch self {
        case .acknowledgeBehaviorImpact,
             .clarifyBoundaryOrNeed,
             .identifyRepairDirection,
             .identifyProtectionDirection,
             .identifyChangeDirection:
            return true
        case .acknowledgeExperience,
             .distinguishFactFromPrediction,
             .softenGlobalSelfJudgment,
             .connectCommonHumanity,
             .synthesizeUnderstanding:
            return false
        }
    }
}

extension TurnReflectionFrame {
    /// Current-v5 Fierce completion is the combination of a Planner-authored direction and the
    /// canonical lived-reality lineage Swift already owns. `behavior` and `impact` remain readable
    /// compatibility details, but they are not repeated current-turn entry requirements.
    var hasCurrentV5GroundedFierceContribution: Bool {
        mode == .fierce
            && fierceEvidence != nil
            && hasNonemptyEvidence
            && hasRealityEvidence
            && hasReflectionDelta
    }
}

/// Mechanical consistency for the one current-v5 reality-to-self-criticism relation.
/// The Planner owns the grounded relationship meaning. Swift owns the canonical stored shape and
/// joins that meaning to the exact current statement instead of asking the model to serialize both.
enum CurrentV5SelfCriticismLineage {
    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Once Reflection has committed a frame, the endpoint already stored in the canonical
    /// difficulty-to-judgment relation is the immutable Reflection anchor. Older v5 builds could
    /// accidentally overwrite `selfCriticalStatement` with a later responsibility or direction;
    /// recovering this endpoint is syntax/provenance repair, not a new semantic interpretation.
    private static func explicitEndpoint(in link: String?) -> String? {
        guard let link = cleaned(link) else { return nil }
        for separator in ["->", "→"] {
            if let range = link.range(of: separator, options: .backwards) {
                return cleaned(String(link[range.upperBound...]))
            }
        }
        return nil
    }

    static func canonicalStatement(in memory: TurnSemanticMemory) -> String? {
        if memory.reflectionFrame != nil,
           let endpoint = explicitEndpoint(in: memory.selfCriticismLink) {
            return endpoint
        }
        return cleaned(memory.selfCriticalStatement)
    }

    static func alignedLink(statement: String?, link: String?) -> String? {
        guard let statement = cleaned(statement),
              let link = cleaned(link) else { return nil }

        // Current output uses an explicit arrow so the endpoint is structurally checkable. The
        // suffix form preserves older saved sessions whose free-text relation already ended in
        // the exact canonical statement before the arrow contract was introduced.
        for separator in ["->", "→"] {
            if let range = link.range(of: separator, options: .backwards) {
                let endpoint = String(link[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return endpoint == statement ? link : nil
            }
        }
        return link.hasSuffix(statement) ? link : nil
    }

    static func compileLink(
        groundedMeaning: String?,
        claimedStatement: String? = nil,
        canonicalStatement: String?
    ) -> String? {
        guard let statement = cleaned(canonicalStatement),
              let meaning = cleaned(groundedMeaning) else { return nil }
        // A provider may redundantly serialize a judgment, but it has no endpoint authority. The
        // exact statement already committed in the session is the only possible target.
        _ = claimedStatement

        // A legacy arrow string still carries one usable grounded side. Normalize its redundant
        // endpoint to the canonical statement instead of making model spelling a transport gate.
        for separator in ["->", "→"] {
            if let range = meaning.range(of: separator, options: .backwards) {
                let grounded = String(meaning[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !grounded.isEmpty, grounded != statement else { return nil }
                return "\(grounded) -> \(statement)"
            }
        }
        if meaning.hasSuffix(statement) {
            return meaning
        }
        guard meaning != statement else { return nil }
        return "\(meaning) -> \(statement)"
    }

    static func alignedLink(
        in memory: TurnSemanticMemory,
        applying update: TurnSemanticMemoryUpdate? = nil
    ) -> String? {
        alignedLink(
            statement: update?.selfCriticalStatement ?? canonicalStatement(in: memory),
            link: update?.selfCriticismLink ?? memory.selfCriticismLink
        )
    }

    /// Saved sessions created before the exact-endpoint contract may have a free-form relation
    /// but no separately persisted statement. Keep those already-entered Reflection sessions
    /// resumable. Once a statement exists, only the exact aligned representation is usable.
    static func committedCompatibleLink(
        in memory: TurnSemanticMemory,
        applying update: TurnSemanticMemoryUpdate? = nil
    ) -> String? {
        let statement = update?.selfCriticalStatement ?? canonicalStatement(in: memory)
        if cleaned(statement) != nil {
            return alignedLink(in: memory, applying: update)
        }
        return cleaned(update?.selfCriticismLink ?? memory.selfCriticismLink)
    }
}

/// The only Planner output accepted by the current v5 runtime. It contains a semantic choice,
/// evidence from the latest user turn, and a writing focus. Workflow fields such as stage,
/// nextPrompt, localAction, replyIntent, and confirmation are intentionally not representable.
struct CurrentV5PlannerOutput: Codable, Equatable, Sendable {
    let semanticOperation: PlannerSemanticOperation
    let semanticEvidencePatch: CurrentV5SemanticEvidencePatch
    let responseFocus: String
    /// Reflection progression meaning only. When present, Swift compiles it into the existing
    /// operation vocabulary; a provider-supplied `semanticOperation` has no authority at that
    /// boundary. The decision is turn-local and is never persisted in semantic memory.
    let reflectionProgressionDecision: CurrentV5ReflectionProgressionDecision?
    /// In-memory compiler provenance only. Remote current-v5 wire responses set this flag even
    /// when the provider omitted the required phase outcome, allowing the Gate to reject that
    /// omission. Directly compiled legacy/test objects remain compatible. This flag is never
    /// encoded, persisted, or sent back to the model.
    let phaseOutcomeContractApplied: Bool

    init(
        semanticOperation: PlannerSemanticOperation,
        semanticEvidencePatch: CurrentV5SemanticEvidencePatch,
        responseFocus: String = "",
        reflectionProgressionDecision: CurrentV5ReflectionProgressionDecision? = nil,
        phaseOutcomeContractApplied: Bool = false
    ) {
        self.semanticOperation = semanticOperation
        self.semanticEvidencePatch = semanticEvidencePatch
        self.responseFocus = responseFocus
        self.reflectionProgressionDecision = reflectionProgressionDecision
        self.phaseOutcomeContractApplied = phaseOutcomeContractApplied
    }

    private enum CodingKeys: String, CodingKey {
        case semanticOperation
        case semanticEvidencePatch
        case responseFocus
        case reflectionProgressionDecision
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        semanticOperation = try box.decode(
            PlannerSemanticOperation.self,
            forKey: .semanticOperation
        )
        semanticEvidencePatch = try box.decode(
            CurrentV5SemanticEvidencePatch.self,
            forKey: .semanticEvidencePatch
        )
        responseFocus = try box.decodeIfPresent(String.self, forKey: .responseFocus) ?? ""
        reflectionProgressionDecision = try box.decodeIfPresent(
            CurrentV5ReflectionProgressionDecision.self,
            forKey: .reflectionProgressionDecision
        )
        phaseOutcomeContractApplied = false
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(semanticOperation, forKey: .semanticOperation)
        try box.encode(semanticEvidencePatch, forKey: .semanticEvidencePatch)
        try box.encode(responseFocus, forKey: .responseFocus)
        try box.encodeIfPresent(
            reflectionProgressionDecision,
            forKey: .reflectionProgressionDecision
        )
    }
}

enum CurrentV5ReflectionProgressionMeaning: String, Codable, Equatable, Sendable {
    case continueExploration
    case completeExploration
    case reviseTender
    case clarifyTender
    case inspectReality
    case clarifyFierce
    case completeFierce
    case synthesize
    case clarifySynthesis
    case acceptSynthesis

    var compiledOperation: PlannerSemanticOperation {
        switch self {
        case .continueExploration, .completeExploration: .continueExploratoryReflection
        case .reviseTender, .clarifyTender: .continueTenderReflection
        case .inspectReality: .continueTenderGroundedFierceReflection
        case .clarifyFierce, .completeFierce: .continueTenderGroundedFierceReflection
        case .synthesize, .clarifySynthesis: .synthesizeDirectReflection
        case .acceptSynthesis: .proposePractice
        }
    }
}

/// Phase-local semantic result reported by the Planner. These values describe what the latest
/// answer means; none of them is a workflow operation or a requested destination phase.
enum CurrentV5ReflectionTurnOutcomeKind: String, Codable, Equatable, Sendable {
    case explorationContinue
    case explorationComplete
    case tenderAccepted
    case tenderRevised
    case tenderNeedsClarification
    case tenderOptedOut
    case fierceNeedsClarification
    case fierceDirectionFormed
    case fierceNoDirection
    case fierceOptedOut
    case synthesisFormed
    case synthesisAccepted
    case synthesisRevised
    case synthesisNeedsClarification
    case synthesisOptedOut
}

/// The Planner identifies one meaningful reality candidate; Swift verifies the stable reference
/// and deterministically opens Fierce. A nil candidate is an explicit semantic judgment that no
/// current reality material warrants Fierce, not an omitted protocol field.
struct CurrentV5RealityCandidateSelection: Codable, Equatable, Sendable {
    let reference: String
    let meaning: TurnRealityCandidateMeaning
}

/// Decode-only normalization for a semantic string returned directly, in a one-value list, or in
/// a common one-owner object wrapper. Multiple distinct values stay unresolved for the Gate.
private struct CurrentV5WireScalarText: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), single.decodeNil() {
            value = nil
            return
        }
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            value = clean.isEmpty ? nil : clean
            return
        }
        if var list = try? decoder.unkeyedContainer() {
            var candidates: [String] = []
            while !list.isAtEnd {
                guard let item = try? list.decode(CurrentV5WireScalarText.self) else {
                    value = nil
                    return
                }
                if let itemValue = item.value { candidates.append(itemValue) }
            }
            let unique = Set(candidates)
            value = unique.count == 1 ? candidates.first : nil
            return
        }
        if let object = try? decoder.container(keyedBy: CurrentV5WireCodingKey.self) {
            let names = [
                "text", "value", "content", "delta", "reflectionDelta", "tenderDelta",
                "synthesisDelta", "fierceDelta", "understanding",
            ]
            let candidates = names.compactMap { name -> String? in
                guard let key = CurrentV5WireCodingKey(stringValue: name),
                      object.contains(key),
                      let decoded = try? object.decode(CurrentV5WireScalarText.self, forKey: key) else {
                    return nil
                }
                return decoded.value
            }
            let unique = Set(candidates)
            value = unique.count == 1 ? candidates.first : nil
            return
        }
        value = nil
    }
}

/// A deliberately flat transport object. Avoiding a discriminated union lets the syntax compiler
/// accept sparse provider JSON and defer phase-specific completeness to Swift's semantic Gate.
private struct CurrentV5ReflectionTurnOutcome: Decodable, Equatable, Sendable {
    let outcome: CurrentV5ReflectionTurnOutcomeKind?
    let selfCriticismLink: CurrentV5WireSelfCriticismLink?
    let tenderDelta: String?
    let synthesisDelta: String?
    let fierceDelta: String?
    let realityCandidate: CurrentV5RealityCandidateSelection?
    let fierceDirection: TurnFierceDirection?
    let hasInvalidRealityCandidate: Bool
    let realityCandidateWasExplicitlyNull: Bool

    private enum CodingKeys: String, CodingKey {
        case outcome, selfCriticismLink, tenderDelta, synthesisDelta, fierceDelta
        case realityCandidate, fierceDirection
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try? box.decode(CurrentV5ReflectionTurnOutcomeKind.self, forKey: .outcome)
        selfCriticismLink = try? box.decodeIfPresent(
            CurrentV5WireSelfCriticismLink.self,
            forKey: .selfCriticismLink
        )
        tenderDelta = (try? box.decode(CurrentV5WireScalarText.self, forKey: .tenderDelta))?.value
        synthesisDelta = (try? box.decode(CurrentV5WireScalarText.self, forKey: .synthesisDelta))?.value
        fierceDelta = (try? box.decode(CurrentV5WireScalarText.self, forKey: .fierceDelta))?.value
        fierceDirection = try? box.decode(TurnFierceDirection.self, forKey: .fierceDirection)

        let candidateIsPresent = box.contains(.realityCandidate)
            && (try? box.decodeNil(forKey: .realityCandidate)) != true
        realityCandidateWasExplicitlyNull = box.contains(.realityCandidate)
            && (try? box.decodeNil(forKey: .realityCandidate)) == true
        if candidateIsPresent {
            realityCandidate = try? box.decode(
                CurrentV5RealityCandidateSelection.self,
                forKey: .realityCandidate
            )
            hasInvalidRealityCandidate = realityCandidate == nil
        } else {
            realityCandidate = nil
            hasInvalidRealityCandidate = false
        }
    }
}

/// The Planner atomically decides the semantic function and, when that function creates an
/// understanding, its delta. Swift owns operation, phase, provenance and protocol representation.
struct CurrentV5ReflectionProgressionDecision: Codable, Equatable, Sendable {
    let meaning: CurrentV5ReflectionProgressionMeaning
    /// `candidateRef` remains a decode-only compatibility field for Tender's inspectReality act.
    /// Active Fierce candidate identity is recovered from Swift-owned pre-turn state instead of
    /// asking the Planner to repeat it.
    let candidateRef: String?
    /// Exploration-completion relationship meaning compiled from the same phase-local outcome as
    /// the initial Tender delta. It is never sourced from a parallel semanticEvidencePatch owner.
    let selfCriticismLink: String?
    let candidateMeaning: TurnRealityCandidateMeaning?
    /// Atomic semantic content for progression acts that create or revise an understanding.
    /// Swift compiles it into the existing reflectionFrame representation; the Planner does not
    /// duplicate the same decision in a distant memoryUpdate field.
    let reflectionDelta: String?
    /// Fierce completion meaning only. The Planner decides which caring direction the latest
    /// answer grounds; Swift compiles it into the existing Fierce frame/action representation.
    let fierceDirection: TurnFierceDirection?
    /// Decode-only compatibility metadata. Current Fierce completion ignores this value and
    /// derives evidence from the active canonical candidate plus the latest unanswered user turn.
    let groundedEvidence: String?

    init(
        meaning: CurrentV5ReflectionProgressionMeaning,
        candidateRef: String?,
        selfCriticismLink: String? = nil,
        candidateMeaning: TurnRealityCandidateMeaning? = nil,
        reflectionDelta: String? = nil,
        fierceDirection: TurnFierceDirection? = nil,
        groundedEvidence: String? = nil
    ) {
        self.meaning = meaning
        self.candidateRef = candidateRef
        self.selfCriticismLink = selfCriticismLink
        self.candidateMeaning = candidateMeaning
        self.reflectionDelta = reflectionDelta
        self.fierceDirection = fierceDirection
        self.groundedEvidence = groundedEvidence
    }
}

/// Syntax-only server transport. Unknown/missing operation spelling is retained until Swift sees
/// the authoritative current capability set; the backend never selects a replacement operation.
private struct CurrentV5PlannerWireOutput: Decodable {
    let semanticOperation: String?
    let semanticEvidencePatch: CurrentV5WireSemanticEvidencePatch
    let responseFocus: String
    let reflectionProgressionDecision: CurrentV5ReflectionProgressionDecision?
    let reflectionTurnOutcome: CurrentV5ReflectionTurnOutcome?

    private enum CodingKeys: String, CodingKey {
        case semanticOperation, semanticEvidencePatch, responseFocus
        case reflectionProgressionDecision, reflectionTurnOutcome
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        semanticOperation = try? box.decodeIfPresent(String.self, forKey: .semanticOperation)
        semanticEvidencePatch = try box.decodeIfPresent(
            CurrentV5WireSemanticEvidencePatch.self,
            forKey: .semanticEvidencePatch
        ) ?? CurrentV5WireSemanticEvidencePatch()
        responseFocus = (try? box.decodeIfPresent(String.self, forKey: .responseFocus)) ?? ""
        reflectionProgressionDecision = try? box.decodeIfPresent(
            CurrentV5ReflectionProgressionDecision.self,
            forKey: .reflectionProgressionDecision
        )
        reflectionTurnOutcome = try? box.decodeIfPresent(
            CurrentV5ReflectionTurnOutcome.self,
            forKey: .reflectionTurnOutcome
        )
    }
}

/// Exact current-v74 transport surface. It contains only model-owned meaning. Persisted protocol
/// aggregates are deliberately absent, so a provider cannot serialize Swift-owned status,
/// provenance, phase, action, identity, or transaction fields even when it tries to do so.
private struct CurrentV5WireEpisodeEvidence: Decodable {
    let concreteFacts: [String]?
    let behaviorEvidence: [String]?
    let eventProcess: [String]?
    let possibleContributors: [String]?
    let contextualConstraints: [String]?
    let controllableParts: [String]?
    let impacts: [String]?
    let keyUncertainty: String?

    var compiled: TurnEpisodeStructure {
        TurnEpisodeStructure(
            concreteFacts: concreteFacts ?? [],
            behaviorEvidence: behaviorEvidence ?? [],
            eventProcess: eventProcess ?? [],
            possibleContributors: possibleContributors ?? [],
            contextualConstraints: contextualConstraints ?? [],
            controllableParts: controllableParts ?? [],
            impacts: impacts ?? [],
            keyUncertainty: keyUncertainty
        )
    }
}

private struct CurrentV5WirePendingConnection: Decodable {
    let imageRelation: String
    let candidateRealityMapping: String
}

private struct CurrentV5WirePracticeProposal: Decodable {
    let content: String
    let basis: String
}

private struct CurrentV5WirePracticeContribution: Decodable {
    let proposal: CurrentV5WirePracticeProposal?
    let noActionReason: TurnNoActionReason?

    var compiled: CurrentV5PracticeContribution {
        CurrentV5PracticeContribution(
            proposal: proposal.map {
                CurrentV5PracticeProposalContribution(
                    content: $0.content,
                    basis: $0.basis
                )
            },
            noActionReason: noActionReason
        )
    }
}

private struct CurrentV5WireCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Decode-only meaning surface. It accepts the legacy string plus common neutral object/tuple
/// spellings without turning the backend into a second semantic compiler. Unknown or conflicting
/// shapes remain unusable rather than throwing a transport error.
private struct CurrentV5WireSelfCriticismLink: Decodable, Equatable, Sendable {
    let groundedMeaning: String?
    let claimedStatement: String?
    let isAmbiguous: Bool

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), single.decodeNil() {
            groundedMeaning = nil
            claimedStatement = nil
            isAmbiguous = false
            return
        }
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            groundedMeaning = value
            claimedStatement = nil
            isAmbiguous = false
            return
        }
        if var values = try? decoder.unkeyedContainer() {
            do {
                let first = try values.decode(String.self)
                let second = values.isAtEnd ? nil : try values.decode(String.self)
                guard values.isAtEnd else {
                    groundedMeaning = nil
                    claimedStatement = nil
                    isAmbiguous = true
                    return
                }
                groundedMeaning = first
                claimedStatement = second
                isAmbiguous = false
            } catch {
                groundedMeaning = nil
                claimedStatement = nil
                isAmbiguous = true
            }
            return
        }
        if let values = try? decoder.container(keyedBy: CurrentV5WireCodingKey.self) {
            let sourceKeys = [
                "groundedDifficulty", "groundedRelation", "difficulty", "pattern", "reality",
                "relationship", "relation", "livedDifficulty", "from",
            ]
            let statementKeys = [
                "selfCriticalStatement", "selfJudgment", "selfCriticism", "judgment",
                "endpoint", "target", "to",
            ]
            func uniqueString(for names: [String]) -> (value: String?, conflicting: Bool) {
                let found = names.compactMap { name -> String? in
                    guard let key = CurrentV5WireCodingKey(stringValue: name),
                          let value = try? values.decodeIfPresent(String.self, forKey: key) else {
                        return nil
                    }
                    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                }
                let unique = Set(found)
                return (unique.count == 1 ? found.first : nil, unique.count > 1)
            }
            let source = uniqueString(for: sourceKeys)
            let statement = uniqueString(for: statementKeys)
            groundedMeaning = source.value
            claimedStatement = statement.value
            isAmbiguous = source.conflicting || source.value == nil
            return
        }
        groundedMeaning = nil
        claimedStatement = nil
        isAmbiguous = true
    }

    func compiled(canonicalStatement: String?) -> String? {
        guard !isAmbiguous else { return nil }
        return CurrentV5SelfCriticismLineage.compileLink(
            groundedMeaning: groundedMeaning,
            claimedStatement: claimedStatement,
            canonicalStatement: canonicalStatement
        )
    }
}

private struct CurrentV5WireSemanticMemoryUpdate: Decodable {
    let situationUnderstanding: String?
    let selfCriticalStatement: String?
    let selfCriticismLink: CurrentV5WireSelfCriticismLink?
    let episodeStructure: CurrentV5WireEpisodeEvidence?
    let contextRelationship: TurnContextRelationship?
    let trackingAssessments: [TurnTrackingAssessment]?
    let pendingCardRealityConnection: CurrentV5WirePendingConnection?
    let cardObservationEvidence: CardObservationEvidence?
    let cardDevelopmentEvidence: CardDevelopmentEvidence?
    let reflectionFrame: CurrentV5ReflectionContribution?
    let invalidatedInterpretations: [String]?
    let finalNarrative: String?
    let practiceTransition: CurrentV5WirePracticeContribution?

    init() {
        situationUnderstanding = nil
        selfCriticalStatement = nil
        selfCriticismLink = nil
        episodeStructure = nil
        contextRelationship = nil
        trackingAssessments = nil
        pendingCardRealityConnection = nil
        cardObservationEvidence = nil
        cardDevelopmentEvidence = nil
        reflectionFrame = nil
        invalidatedInterpretations = nil
        finalNarrative = nil
        practiceTransition = nil
    }

    func compiled(canonicalSelfCriticalStatement: String?) -> TurnSemanticMemoryUpdate {
        let statement = selfCriticalStatement ?? canonicalSelfCriticalStatement
        return TurnSemanticMemoryUpdate(
            situationUnderstanding: situationUnderstanding,
            selfCriticalStatement: selfCriticalStatement,
            selfCriticismLink: selfCriticismLink?.compiled(canonicalStatement: statement),
            episodeStructure: episodeStructure?.compiled,
            contextRelationship: contextRelationship,
            trackingAssessments: trackingAssessments,
            pendingCardRealityConnection: pendingCardRealityConnection.map {
                PendingCardRealityConnection(
                    imageRelation: $0.imageRelation,
                    candidateRealityMapping: $0.candidateRealityMapping
                )
            },
            cardObservationEvidence: cardObservationEvidence,
            cardDevelopmentEvidence: cardDevelopmentEvidence,
            invalidatedInterpretations: invalidatedInterpretations,
            finalNarrative: finalNarrative
        )
    }
}

private struct CurrentV5WireSemanticEvidencePatch: Decodable {
    let memoryUpdate: CurrentV5WireSemanticMemoryUpdate
    let cardConnectionEvidence: CurrentV5CardConnectionEvidence?
    let contextualTrackingDecision: CurrentV5ContextualTrackingDecision?

    init() {
        memoryUpdate = CurrentV5WireSemanticMemoryUpdate()
        cardConnectionEvidence = nil
        contextualTrackingDecision = nil
    }

    func compiled(canonicalSelfCriticalStatement: String?) -> CurrentV5SemanticEvidencePatch {
        CurrentV5SemanticEvidencePatch(
            memoryUpdate: memoryUpdate.compiled(
                canonicalSelfCriticalStatement: canonicalSelfCriticalStatement
            ),
            cardConnectionEvidence: cardConnectionEvidence,
            reflectionContribution: memoryUpdate.reflectionFrame,
            practiceContribution: memoryUpdate.practiceTransition?.compiled,
            contextualTrackingDecision: contextualTrackingDecision
        )
    }
}

/// Sole provider-output compiler. The wire surface carries meaning only; Swift resolves an absent
/// or unknown operation spelling when committed pre-turn capability has exactly one answer.
func decodeCurrentV5PlannerWireOutput(
    _ data: Data,
    allowedSemanticOperations: [PlannerSemanticOperation],
    canonicalSelfCriticalStatement: String? = nil,
    pendingRealityCandidate: TurnPendingRealityCandidate? = nil
) throws -> CurrentV5PlannerOutput {
    let wire = try JSONDecoder().decode(CurrentV5PlannerWireOutput.self, from: data)
    let supplied = wire.semanticOperation.flatMap(PlannerSemanticOperation.init(rawValue:))
    var semanticPatch = wire.semanticEvidencePatch.compiled(
        canonicalSelfCriticalStatement: canonicalSelfCriticalStatement
    )
    var progression: CurrentV5ReflectionProgressionDecision?

    // Current Reflection requests carry a phase-local semantic outcome rather than asking the
    // model to select a workflow operation. This is the sole operation compiler for that outcome.
    // The former progression object remains decode-only compatibility and has no equal authority
    // when the canonical outcome is present.
    if let outcome = wire.reflectionTurnOutcome,
       let outcomeKind = outcome.outcome {
        if [.explorationContinue, .explorationComplete].contains(outcomeKind) {
            // Exploration completion meaning has one owner. Any parallel patch link is redundant
            // residue and cannot make an otherwise self-contained outcome pass or fail.
            semanticPatch.memoryUpdate.selfCriticismLink = nil
        }
        // A reality candidate is optional enrichment attached to an otherwise complete
        // Reflection outcome. Provider syntax that cannot identify one candidate must not erase
        // the outcome's canonical link/delta or turn a usable semantic response into transport
        // failure. Swift still validates any successfully decoded candidate against grounded
        // provenance below.
        let outcomeCandidate = outcome.hasInvalidRealityCandidate
            ? nil
            : outcome.realityCandidate
        let outcomeLink = outcome.selfCriticismLink?.compiled(
            canonicalStatement: semanticPatch.memoryUpdate.selfCriticalStatement
                ?? canonicalSelfCriticalStatement
        )
        progression = switch outcomeKind {
        case .explorationContinue:
            CurrentV5ReflectionProgressionDecision(
                meaning: .continueExploration,
                candidateRef: nil
            )
        case .explorationComplete:
            CurrentV5ReflectionProgressionDecision(
                meaning: .completeExploration,
                candidateRef: outcomeCandidate?.reference,
                selfCriticismLink: outcomeLink,
                candidateMeaning: outcomeCandidate?.meaning,
                reflectionDelta: outcome.tenderDelta
            )
        case .tenderAccepted, .tenderRevised:
            if let candidate = outcome.realityCandidate {
                CurrentV5ReflectionProgressionDecision(
                    meaning: .inspectReality,
                    candidateRef: candidate.reference,
                    candidateMeaning: candidate.meaning,
                    reflectionDelta: outcomeKind == .tenderRevised
                        ? outcome.tenderDelta
                        : nil
                )
            } else if !outcome.hasInvalidRealityCandidate,
                      !outcome.realityCandidateWasExplicitlyNull,
                      let pendingRealityCandidate {
                CurrentV5ReflectionProgressionDecision(
                    meaning: .inspectReality,
                    candidateRef: pendingRealityCandidate.reference,
                    candidateMeaning: pendingRealityCandidate.meaning,
                    reflectionDelta: outcomeKind == .tenderRevised
                        ? outcome.tenderDelta
                        : nil
                )
            } else {
                // Acceptance never becomes another Tender clarification merely because optional
                // candidate syntax is unusable. Preserve the accepted outcome and let the Swift
                // Gate request a missing explicit Synthesis delta when no grounded candidate can
                // be compiled. This prevents protocol incompleteness from silently reopening the
                // same confirmation loop.
                CurrentV5ReflectionProgressionDecision(
                    meaning: .synthesize,
                    candidateRef: nil,
                    reflectionDelta: outcome.synthesisDelta
                )
            }
        case .tenderNeedsClarification:
            CurrentV5ReflectionProgressionDecision(
                meaning: .clarifyTender,
                candidateRef: nil
            )
        case .tenderOptedOut:
            CurrentV5ReflectionProgressionDecision(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: outcome.synthesisDelta
            )
        case .fierceNeedsClarification:
            CurrentV5ReflectionProgressionDecision(
                meaning: .clarifyFierce,
                candidateRef: nil
            )
        case .fierceDirectionFormed:
            CurrentV5ReflectionProgressionDecision(
                meaning: .completeFierce,
                candidateRef: nil,
                reflectionDelta: outcome.fierceDelta,
                fierceDirection: outcome.fierceDirection
            )
        case .fierceNoDirection, .fierceOptedOut:
            CurrentV5ReflectionProgressionDecision(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: outcome.synthesisDelta
            )
        case .synthesisFormed, .synthesisRevised:
            CurrentV5ReflectionProgressionDecision(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: outcome.synthesisDelta
            )
        case .synthesisNeedsClarification:
            CurrentV5ReflectionProgressionDecision(
                meaning: .clarifySynthesis,
                candidateRef: nil
            )
        case .synthesisAccepted, .synthesisOptedOut:
            CurrentV5ReflectionProgressionDecision(
                meaning: .acceptSynthesis,
                candidateRef: nil
            )
        }
    } else {
        progression = wire.reflectionProgressionDecision
    }

    // Providers may still serialize an older separated Reflection shape. When the semantic act
    // has exactly one interpretation, compile that shape here instead of making transport syntax
    // a user-visible failure. This compiler never invents a delta, direction, candidate, or next
    // phase: it only colocates meaning already supplied by the model. Ambiguous shapes remain
    // unresolved for the Gate/correction path.
    if progression == nil {
        let contribution = semanticPatch.reflectionContribution
        let delta = contribution?.reflectionDelta?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonemptyDelta = delta?.isEmpty == false ? delta : nil
        let direction = contribution?.fierceEvidence?.direction
        let focus = wire.responseFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeFierceShape =
            allowedSemanticOperations.contains(.continueTenderGroundedFierceReflection)
            && !allowedSemanticOperations.contains(.continueTenderReflection)

        if (supplied == .continueTenderGroundedFierceReflection
                || supplied == nil && activeFierceShape),
           let nonemptyDelta,
           let direction {
            progression = CurrentV5ReflectionProgressionDecision(
                meaning: .completeFierce,
                candidateRef: nil,
                reflectionDelta: nonemptyDelta,
                fierceDirection: direction
            )
        } else if activeFierceShape,
                  (supplied == .continueTenderGroundedFierceReflection || supplied == nil),
                  nonemptyDelta == nil,
                  direction == nil,
                  !focus.isEmpty {
            progression = CurrentV5ReflectionProgressionDecision(
                meaning: .clarifyFierce,
                candidateRef: nil
            )
        } else if supplied == .synthesizeDirectReflection,
                  let nonemptyDelta,
                  direction == nil {
            progression = CurrentV5ReflectionProgressionDecision(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: nonemptyDelta
            )
        } else if supplied == .continueTenderReflection,
                  allowedSemanticOperations.count > 1,
                  let nonemptyDelta,
                  direction == nil {
            progression = CurrentV5ReflectionProgressionDecision(
                meaning: .reviseTender,
                candidateRef: nil,
                reflectionDelta: nonemptyDelta
            )
        }
    }

    let operation: PlannerSemanticOperation
    if let progression {
        let compiled = progression.meaning.compiledOperation
        operation = compiled
    } else if let supplied {
        operation = supplied
    } else if let deterministicNonsemanticFallback = allowedSemanticOperations.first {
        // Missing protocol structure in an otherwise decoded semantic object belongs to the
        // semantic compiler/Gate. Selecting an already-authorized current act here supplies no
        // meaning or transition; `phaseOutcomeContractApplied` makes the Gate reject/repair the
        // missing phase outcome, after which the bounded continuity path remains available.
        operation = deterministicNonsemanticFallback
    } else {
        throw CurrentV5RemoteContractError.plannerContractInvalid
    }
    if let progression {
        switch progression.meaning {
        case .continueExploration, .clarifyTender, .clarifyFierce, .clarifySynthesis,
             .acceptSynthesis:
            // An inquiry has no Reflection conclusion. Redundant legacy content cannot become a
            // second contribution owner merely because the operation changes phase.
            semanticPatch.memoryUpdate.reflectionFrame = nil
            semanticPatch.reflectionContribution = nil
        case .completeExploration:
            semanticPatch.memoryUpdate.reflectionFrame = nil
            semanticPatch.reflectionContribution = progression.reflectionDelta.map {
                CurrentV5ReflectionContribution(reflectionDelta: $0)
            }
        case .inspectReality:
            semanticPatch.memoryUpdate.reflectionFrame = nil
            semanticPatch.reflectionContribution = progression.reflectionDelta.map {
                CurrentV5ReflectionContribution(reflectionDelta: $0)
            }
        case .completeFierce:
            // The Planner owns only completion meaning, direction, and delta. Candidate identity,
            // current user evidence, lineage, and the canonical frame are compiled later by Swift
            // from the authoritative pre-turn session.
            semanticPatch.memoryUpdate.reflectionFrame = nil
            semanticPatch.reflectionContribution = nil
        case .reviseTender, .synthesize:
            if progression.reflectionDelta != nil {
                // The colocated delta is canonical. Separately emitted legacy content has no
                // equal authority, even when the two strings conflict.
                semanticPatch.memoryUpdate.reflectionFrame = nil
                semanticPatch.reflectionContribution = CurrentV5ReflectionContribution(
                    reflectionDelta: progression.reflectionDelta
                )
            }
        }
    }
    return CurrentV5PlannerOutput(
        semanticOperation: operation,
        semanticEvidencePatch: semanticPatch,
        responseFocus: wire.responseFocus,
        reflectionProgressionDecision: progression,
        phaseOutcomeContractApplied: true
    )
}

enum CurrentV5TrackingMetricEligibilityStatus: String, Codable, Equatable, Sendable {
    case qualifies
    case doesNotQualify
}

struct CurrentV5TrackingMetricEligibility: Codable, Equatable, Sendable {
    let profileID: String
    let metric: String
    let status: CurrentV5TrackingMetricEligibilityStatus
    let preferred: Bool

    var reference: ContextualTrackingMetricIdentity {
        ContextualTrackingMetricIdentity(profileID: profileID, metric: metric)
    }
}

/// Turn-local Planner meaning over every exact metric supplied in the request. Swift validates
/// complete coverage and compiles the sole preferred qualifying metric into the existing
/// nil / reviewed-not-used / selected Tracking review state.
struct CurrentV5ContextualTrackingDecision: Codable, Equatable, Sendable {
    let metricEligibility: [CurrentV5TrackingMetricEligibility]

    var preferredMetricReference: ContextualTrackingMetricIdentity? {
        let qualifying = metricEligibility.filter { $0.status == .qualifies }
        let explicitlyPreferred = qualifying.filter(\.preferred)
        if explicitlyPreferred.count == 1 {
            return explicitlyPreferred[0].reference
        }
        if qualifying.count == 1 {
            return qualifying[0].reference
        }
        return nil
    }

}

/// Planner-authored Card meaning only. Swift combines it with committed user-authored image
/// development and assigns connection provenance/status from the current interaction.
struct CurrentV5CardConnectionEvidence: Codable, Equatable, Sendable {
    let imageRelation: String?
    let realityMapping: String?
}

struct CurrentV5FierceContribution: Codable, Equatable, Sendable {
    let behavior: String?
    let impact: String?
    let direction: TurnFierceDirection?
}

/// Semantic Reflection contribution. Internal frame mode/action/provenance are intentionally not
/// representable at this boundary; the Swift compiler restores them from the current act/state.
struct CurrentV5ReflectionContribution: Codable, Equatable, Sendable {
    let evidenceBasis: [String]
    let dimensions: [TurnSelfCompassionDimension]
    let reflectionDelta: String?
    let fierceEvidence: CurrentV5FierceContribution?

    private enum CodingKeys: String, CodingKey {
        case evidenceBasis, dimensions, reflectionDelta, fierceEvidence
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? box.decode([String].self, forKey: .evidenceBasis) {
            evidenceBasis = values
        } else if let legacy = try? box.decode(
            [TurnReflectionEvidence].self,
            forKey: .evidenceBasis
        ) {
            evidenceBasis = legacy.map(\.content)
        } else {
            evidenceBasis = []
        }
        dimensions = (try? box.decode(
            [TurnSelfCompassionDimension].self,
            forKey: .dimensions
        )) ?? []
        reflectionDelta = try? box.decodeIfPresent(String.self, forKey: .reflectionDelta)
        fierceEvidence = try? box.decodeIfPresent(
            CurrentV5FierceContribution.self,
            forKey: .fierceEvidence
        )
    }

    init(
        evidenceBasis: [String] = [],
        dimensions: [TurnSelfCompassionDimension] = [],
        reflectionDelta: String? = nil,
        fierceEvidence: CurrentV5FierceContribution? = nil
    ) {
        self.evidenceBasis = evidenceBasis
        self.dimensions = dimensions
        self.reflectionDelta = reflectionDelta
        self.fierceEvidence = fierceEvidence
    }

    /// An empty transport object carries no Reflection meaning and is equivalent to omission.
    /// Any actual evidence, dimension, delta, or Fierce direction is an attempted contribution and
    /// must satisfy the current act's complete semantic contract.
    var hasSemanticContent: Bool {
        evidenceBasis.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
            || !dimensions.isEmpty
            || reflectionDelta?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || fierceEvidence != nil
    }
}

struct CurrentV5PracticeProposalContribution: Codable, Equatable, Sendable {
    /// Decode-only compatibility. Current-v74 output omits protocol kind; Swift derives it from
    /// the last committed grounded Fierce direction, or uses care when no such direction exists.
    let kind: TurnPracticeKind?
    let content: String
    let basis: String

    init(kind: TurnPracticeKind? = nil, content: String, basis: String) {
        self.kind = kind
        self.content = content
        self.basis = basis
    }
}

struct CurrentV5PracticeContribution: Codable, Equatable, Sendable {
    let proposal: CurrentV5PracticeProposalContribution?
    let noActionReason: TurnNoActionReason?
}

struct CurrentV5SemanticEvidencePatch: Codable, Equatable, Sendable {
    var memoryUpdate: TurnSemanticMemoryUpdate
    var cardConnectionEvidence: CurrentV5CardConnectionEvidence?
    var reflectionContribution: CurrentV5ReflectionContribution?
    var practiceContribution: CurrentV5PracticeContribution?
    /// Decode/test compatibility only. Current-v72 Planner output cannot write this tagged union.
    var cardConnectionTurnOutcome: CardConnectionTurnOutcome?
    var contextualTrackingDecision: CurrentV5ContextualTrackingDecision?

    init(
        memoryUpdate: TurnSemanticMemoryUpdate = TurnSemanticMemoryUpdate(),
        cardConnectionEvidence: CurrentV5CardConnectionEvidence? = nil,
        reflectionContribution: CurrentV5ReflectionContribution? = nil,
        practiceContribution: CurrentV5PracticeContribution? = nil,
        cardConnectionTurnOutcome: CardConnectionTurnOutcome? = nil,
        contextualTrackingDecision: CurrentV5ContextualTrackingDecision? = nil
    ) {
        self.memoryUpdate = memoryUpdate
        self.cardConnectionEvidence = cardConnectionEvidence
        self.reflectionContribution = reflectionContribution
        self.practiceContribution = practiceContribution
        self.cardConnectionTurnOutcome = cardConnectionTurnOutcome
        self.contextualTrackingDecision = contextualTrackingDecision
    }

    private enum CodingKeys: String, CodingKey {
        case memoryUpdate
        case cardConnectionEvidence
        case reflectionContribution
        case practiceContribution
        case cardConnectionTurnOutcome
        case contextualTrackingDecision
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        memoryUpdate = try box.decodeIfPresent(
            TurnSemanticMemoryUpdate.self,
            forKey: .memoryUpdate
        ) ?? TurnSemanticMemoryUpdate()
        cardConnectionEvidence = try box.decodeIfPresent(
            CurrentV5CardConnectionEvidence.self,
            forKey: .cardConnectionEvidence
        )
        let memoryBox = try? box.nestedContainer(
            keyedBy: SemanticMemoryCodingKeys.self,
            forKey: .memoryUpdate
        )
        reflectionContribution = try box.decodeIfPresent(
            CurrentV5ReflectionContribution.self,
            forKey: .reflectionContribution
        ) ?? memoryBox.flatMap {
            try? $0.decodeIfPresent(
                CurrentV5ReflectionContribution.self,
                forKey: .reflectionFrame
            )
        }
        practiceContribution = try box.decodeIfPresent(
            CurrentV5PracticeContribution.self,
            forKey: .practiceContribution
        ) ?? memoryBox.flatMap {
            try? $0.decodeIfPresent(
                CurrentV5PracticeContribution.self,
                forKey: .practiceTransition
            )
        }
        cardConnectionTurnOutcome = try box.decodeIfPresent(
            CardConnectionTurnOutcome.self,
            forKey: .cardConnectionTurnOutcome
        )
        contextualTrackingDecision = try box.decodeIfPresent(
            CurrentV5ContextualTrackingDecision.self,
            forKey: .contextualTrackingDecision
        )
    }

    private enum SemanticMemoryCodingKeys: String, CodingKey {
        case reflectionFrame
        case practiceTransition
    }
}

struct CurrentV5TranscriptItem: Codable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let replyToMessageID: UUID?
}

/// The only persisted semantic evidence visible to the current-v5 Planner. This is a deterministic
/// read projection, not another state store: Swift keeps interaction/execution metadata in the
/// session, while the Planner receives only evidence it may legitimately use to understand a turn.
struct CurrentV5PlannerMemory: Codable, Equatable, Sendable {
    let situationUnderstanding: String?
    let answeredQuestionPurposes: [String]?
    let receivedDisclosureQuestionPurposes: [TurnDisclosureQuestionPurpose]?
    let eventDisclosureOutcome: TurnEventDisclosureOutcome
    let selfCriticismStatus: TurnSelfCriticismStatus
    let selfCriticalStatement: String?
    let selfCriticismLink: String?
    let pendingRealityCandidate: TurnPendingRealityCandidate?
    let episodeStructure: TurnEpisodeStructure?
    let contextRelationship: TurnContextRelationship?
    let trackingAssessments: [TurnTrackingAssessment]?
    let cardRealityConnection: TurnCardRealityConnection?
    let pendingCardRealityConnection: PendingCardRealityConnection?
    let cardObservationEvidence: CardObservationEvidence?
    let cardDevelopmentEvidence: CardDevelopmentEvidence?
    let reflectionFrame: TurnReflectionFrame?
    let invalidatedInterpretations: [String]?
    let finalNarrative: String?
    let practiceTransition: TurnPracticeTransition?

    init(_ source: TurnSemanticMemory) {
        let understanding = source.situationUnderstanding
            .trimmingCharacters(in: .whitespacesAndNewlines)
        situationUnderstanding = understanding.isEmpty ? nil : understanding
        answeredQuestionPurposes = source.answeredQuestionPurposes.isEmpty
            ? nil
            : source.answeredQuestionPurposes
        receivedDisclosureQuestionPurposes = source.receivedDisclosureQuestionPurposes.isEmpty
            ? nil
            : source.receivedDisclosureQuestionPurposes
        eventDisclosureOutcome = source.eventDisclosureOutcome
        selfCriticismStatus = source.selfCriticismStatus
        selfCriticalStatement = CurrentV5SelfCriticismLineage.canonicalStatement(in: source)
        selfCriticismLink = source.selfCriticismLink
        pendingRealityCandidate = source.pendingRealityCandidate
        episodeStructure = source.episodeStructure
        contextRelationship = source.contextRelationship
        trackingAssessments = source.trackingAssessments.isEmpty ? nil : source.trackingAssessments
        cardRealityConnection = source.cardRealityConnection?.normalizedConfirmed
        pendingCardRealityConnection = source.pendingCardRealityConnection
        cardObservationEvidence = source.cardObservationEvidence
        cardDevelopmentEvidence = source.cardDevelopmentEvidence
        reflectionFrame = source.reflectionFrame
        invalidatedInterpretations = source.invalidatedInterpretations.isEmpty
            ? nil
            : source.invalidatedInterpretations
        finalNarrative = source.finalNarrative
        practiceTransition = source.practiceTransition
    }
}

/// Turn-local identity of the visible interaction the latest user message answers. It is derived
/// from Swift-owned state, never persisted separately, never writable by the Planner, and carries
/// no wording or executable instruction from `nextPrompt`.
struct CurrentV5LatestAnswerContext: Codable, Equatable, Sendable {
    let purpose: String?
    let disclosurePurpose: TurnDisclosureQuestionPurpose?
    let referenceID: String?

    init(_ prompt: TurnNextPrompt) {
        purpose = prompt.purpose
        disclosurePurpose = prompt.disclosurePurpose
        referenceID = prompt.referenceID
    }
}

enum CurrentV5GroundedRealityCandidateSource: String, Codable, Equatable, Sendable {
    case episode
    case cardRealityConnection
    case confirmedContext
    case reflectionEvidence
}

/// A deterministic read projection of canonical user-grounded reality. Field paths provide stable
/// references; Swift does not label a candidate as support, responsibility, change, or otherwise
/// decide whether it is meaningful for Fierce reflection.
struct CurrentV5GroundedRealityCandidate: Codable, Equatable, Sendable {
    let id: String
    let source: CurrentV5GroundedRealityCandidateSource
    let content: String
    let cardAuthorship: TurnCardRealityMappingSource?

    static func projected(
        from memory: TurnSemanticMemory,
        applying update: TurnSemanticMemoryUpdate? = nil
    ) -> [Self] {
        var result: [Self] = []
        var seenContent = Set<String>()

        func append(
            id: String,
            source: CurrentV5GroundedRealityCandidateSource,
            content: String,
            cardAuthorship: TurnCardRealityMappingSource? = nil
        ) {
            let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seenContent.insert(clean).inserted else { return }
            result.append(
                .init(
                    id: id,
                    source: source,
                    content: clean,
                    cardAuthorship: cardAuthorship
                )
            )
        }

        let episode: TurnEpisodeStructure? = {
            guard let patch = update?.episodeStructure else { return memory.episodeStructure }
            return memory.episodeStructure?.merging(patch) ?? patch
        }()
        if let episode {
            let fields: [(String, [String])] = [
                ("concreteFacts", episode.concreteFacts),
                ("behaviorEvidence", episode.behaviorEvidence),
                ("eventProcess", episode.eventProcess),
                ("possibleContributors", episode.possibleContributors),
                ("contextualConstraints", episode.contextualConstraints),
                ("controllableParts", episode.controllableParts),
                ("impacts", episode.impacts),
            ]
            for (field, values) in fields {
                for (index, value) in values.enumerated() {
                    append(
                        id: "episodeStructure.\(field).\(index)",
                        source: .episode,
                        content: value
                    )
                }
            }
        }

        if let connection = (update?.cardRealityConnection
            ?? memory.cardRealityConnection)?.normalizedConfirmed {
            append(
                id: "cardRealityConnection.realityMapping",
                source: .cardRealityConnection,
                content: connection.realityMapping,
                cardAuthorship: connection.source
            )
        }

        let context = update?.contextRelationship ?? memory.contextRelationship
        if let context,
           [.related, .partlyRelated].contains(context.relevance),
           let interpretation = context.userInterpretation {
            append(
                id: "contextRelationship.userInterpretation",
                source: .confirmedContext,
                content: interpretation
            )
        }

        let frame = update?.reflectionFrame ?? memory.reflectionFrame
        if let frame {
            for (index, evidence) in frame.evidenceBasis.enumerated() {
                let source: CurrentV5GroundedRealityCandidateSource? = switch evidence.source {
                case .episode, .latestUserAnswer: .reflectionEvidence
                case .confirmedContext: .confirmedContext
                case .cardRealityConnection: nil
                }
                if let source {
                    append(
                        id: "reflectionFrame.evidenceBasis.\(index)",
                        source: source,
                        content: evidence.content
                    )
                }
            }
        }
        return result
    }
}

/// A compact request for the current runtime. It deliberately omits the legacy executable
/// permission tuples. The model sees only the semantic operations currently available to it.
struct CurrentV5TurnRequest: Codable, Equatable, Sendable {
    let trigger: LLMTurnTrigger
    let protocolVersion: Int
    let protocolStage: ReflectionProtocolStage
    let condition: ExperimentalCondition
    let allowedSemanticOperations: [PlannerSemanticOperation]
    let recentMessages: [CurrentV5TranscriptItem]
    let semanticMemory: CurrentV5PlannerMemory
    /// Swift-owned current reflection substate exposed read-only, outside writable semantic memory.
    let reflectionMode: TurnReflectionPhase?
    let groundedRealityCandidates: [CurrentV5GroundedRealityCandidate]?
    let latestAnswerContext: CurrentV5LatestAnswerContext?
    let contextualTrackingProfiles: [LLMTurnContextualTrackingProfile]?
    let eventAnchorDate: String?
    private(set) var card: LLMTurnCardContext?
    let correction: CurrentV5PlannerCorrection?

    init(
        base: LLMTurnControllerRequest,
        messages: [ChatMessage],
        allowedSemanticOperations: [PlannerSemanticOperation],
        correction: CurrentV5PlannerCorrection? = nil
    ) {
        trigger = base.trigger
        protocolVersion = base.protocolVersion
        protocolStage = base.protocolStage
        condition = base.condition
        self.allowedSemanticOperations = allowedSemanticOperations
        recentMessages = messages
            .suffix(18)
            .map {
                CurrentV5TranscriptItem(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    replyToMessageID: $0.replyToMessageID
                )
            }
        semanticMemory = CurrentV5PlannerMemory(base.semanticMemory)
        reflectionMode = base.protocolStage == .directReflection
            ? base.semanticMemory.reflectionPhase
            : nil
        let candidates = CurrentV5GroundedRealityCandidate.projected(
            from: base.semanticMemory
        )
        groundedRealityCandidates = candidates.isEmpty ? nil : candidates
        if base.trigger == .userMessage,
           messages.last?.role == .user,
           let prompt = base.semanticMemory.nextPrompt,
           prompt.kind != .none {
            latestAnswerContext = CurrentV5LatestAnswerContext(prompt)
        } else {
            latestAnswerContext = nil
        }
        contextualTrackingProfiles = base.contextualTrackingProfiles.isEmpty
            ? nil
            : base.contextualTrackingProfiles
        eventAnchorDate = base.eventAnchorDate
        card = base.card?.currentV5ReplacingVisualScaffolds(
            allowedSemanticOperations.contains(.offerCardConnectionScaffold)
                ? base.card?.visualScaffolds ?? []
                : []
        )
        self.correction = correction
    }

    /// Writer sees a visual scaffold only while realizing the exact Swift-authorized scaffold act.
    /// Planner access is already capability-scoped above; this second projection prevents the full
    /// planning request from leaking an unused scaffold into ordinary visible Card language.
    func scopedForWriter(operation: PlannerSemanticOperation) -> Self {
        var scoped = self
        if operation != .offerCardConnectionScaffold {
            scoped.card = card?.currentV5ReplacingVisualScaffolds([])
        }
        return scoped
    }
}

extension LLMTurnCardContext {
    func currentV5ReplacingVisualScaffolds(
        _ visualScaffolds: [CardVisualScaffold]
    ) -> Self {
        Self(
            imageIsDisplayed: imageIsDisplayed,
            imageDevelopmentTurnCount: imageDevelopmentTurnCount,
            connectionAttemptCount: connectionAttemptCount,
            connectionScaffoldUsed: connectionScaffoldUsed,
            connectionUnavailable: connectionUnavailable,
            connectionInteractionState: connectionInteractionState,
            realityAnchor: realityAnchor,
            visualScaffolds: visualScaffolds,
            reflectionApproaches: reflectionApproaches,
            referenceGuidance: referenceGuidance,
            prohibitedClaims: prohibitedClaims
        )
    }
}

extension LLMTurnContextualTrackingProfile {
    /// Projects all available supported domains into compact temporal facts for one possible
    /// current-v5 contextual reveal. The confirmed Card connection opens the reflection-time window;
    /// it is not an input to Tracking relevance. Swift performs only cleaning, aggregation, baseline
    /// arithmetic and coverage counting. It does not decide whether a profile could have affected
    /// the focal event or label its quality, meaning or relevance.
    static func currentV5Profiles(in session: ReflectionSession) -> [Self] {
        // Tracking is an independent contextual branch. A missing review stays available through
        // Tender, but it never determines whether Exploration or Tender itself may progress.
        let reflectionWindowIsOpen = [TurnReflectionPhase.exploratory, .tender]
            .contains(session.semanticMemory.reflectionPhase)
        guard session.protocolVersion >= ReflectionSession.currentProtocolVersion,
              session.protocolStage == .directReflection,
              reflectionWindowIsOpen,
              session.condition.usesCard,
              session.cardGuidanceShared,
              session.semanticMemory.cardRealityConnection?.normalizedConfirmed != nil,
              (session.contextualLoadInference?.relevance ?? .notReviewed) == .notReviewed else {
            return []
        }

        let eligibleCues = session.trackingCues.filter {
            $0.relevance == .notReviewed && ($0.insight?.validSampleCount ?? 0) > 0
        }
        let groups: [(domain: String, metrics: [TrackingMetric])] = [
            ("sleep", [.sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity]),
            ("calendar", [.calendarLoad]),
            ("hrv", [.heartRateVariability]),
            ("activity", [.steps]),
        ]
        return groups.compactMap { group in
            var profiles = group.metrics.compactMap { metric in
                metric.currentV5TemporalProfile(from: eligibleCues)
            }
            if group.domain == "calendar",
               let series = eligibleCues.first(where: {
                   $0.insight?.metric == .calendarLoad
               })?.metrics?.supplementalSeries {
                profiles.append(contentsOf: series.compactMap(\.currentV5TemporalProfile))
            }
            return profiles.isEmpty
                ? nil
                : Self(profileID: group.domain, domain: group.domain, metrics: profiles)
        }
    }
}

private extension TrackingSupplementalSeries {
    var currentV5TemporalProfile: LLMTurnTemporalMetricProfile? {
        let sorted = daily.sorted { $0.date < $1.date }
        let recentPoints = Array(sorted.suffix(7))
        let baselinePoints = Array(sorted.dropLast(recentPoints.count).suffix(28))
        let recentDaily = recentPoints.compactMap { point -> LLMTurnTemporalDataPoint? in
            guard let value = point.value, value.isFinite else { return nil }
            return .init(
                date: TrackingMetric.currentV5DayString(point.date),
                value: value,
                sampleCount: max(point.count, 0)
            )
        }
        let recentValues = recentDaily.map(\.value)
        guard !recentValues.isEmpty else { return nil }
        let baselineValues = baselinePoints.compactMap { point -> Double? in
            guard let value = point.value, value.isFinite else { return nil }
            return value
        }
        let includesUsefulTotal = [
            "calendarEventCount",
            "calendarBackToBackPairs",
            "calendarEveningScheduled",
        ].contains(metric)
        return LLMTurnTemporalMetricProfile(
            metric: metric,
            unit: unit,
            recentDaily: recentDaily,
            recentMedian: TrackingStatistics.median(recentValues),
            recentTotal: includesUsefulTotal ? recentValues.reduce(0, +) : nil,
            recentRecordCount: nil,
            baselineMedian: baselineValues.isEmpty
                ? nil
                : TrackingStatistics.median(baselineValues),
            coverage: .init(
                recentObservedDays: recentDaily.count,
                recentExpectedDays: 7,
                recentSampleCount: recentDaily.reduce(0) { $0 + $1.sampleCount },
                baselineObservedDays: baselineValues.count,
                baselineExpectedDays: 28
            )
        )
    }
}

private extension TrackingMetric {
    var currentV5Unit: String {
        switch self {
        case .sleepDuration: "hours"
        case .sleepTiming, .sleepWakeTime: "localClockHour"
        case .sleepContinuity: "recordedSleepFraction"
        case .heartRateVariability: "ms"
        case .steps: "steps"
        case .calendarLoad: "scheduledHours"
        case .restingHeartRate: "bpm"
        case .screenTime: "hours"
        case .weather: "sourceUnit"
        }
    }

    func currentV5TemporalProfile(
        from cues: [TrackingCue]
    ) -> LLMTurnTemporalMetricProfile? {
        guard let cue = cues.first(where: { $0.insight?.metric == self }),
              let insight = cue.insight else {
            return nil
        }
        let points = (insight.recentDailyPoints ?? cue.metrics?.daily ?? [])
            .sorted { $0.date < $1.date }
            .suffix(max(insight.expectedSampleCount, 1))
        let recentDaily = points.compactMap { point -> LLMTurnTemporalDataPoint? in
            guard let value = point.value, value.isFinite else { return nil }
            return LLMTurnTemporalDataPoint(
                date: Self.currentV5DayString(point.date),
                value: value,
                sampleCount: max(point.count, 0)
            )
        }
        guard !recentDaily.isEmpty || insight.recentMedian != nil else { return nil }
        let baselineObserved = insight.baselineObservedDays
            ?? (insight.baselineMedian == nil ? 0 : 1)
        let baselineExpected = insight.baselineExpectedDays
            ?? (insight.baselineWindow == nil ? 0 : 28)
        return LLMTurnTemporalMetricProfile(
            metric: rawValue,
            unit: currentV5Unit,
            recentDaily: recentDaily,
            recentMedian: insight.recentMedian ?? cue.metrics?.summaryValue,
            recentTotal: insight.recentTotal,
            recentRecordCount: insight.recentRecordCount,
            baselineMedian: insight.factualBaselineMedian ?? insight.baselineMedian,
            coverage: LLMTurnTemporalCoverage(
                recentObservedDays: recentDaily.count,
                recentExpectedDays: max(insight.expectedSampleCount, 0),
                recentSampleCount: recentDaily.reduce(0) { $0 + $1.sampleCount },
                baselineObservedDays: max(baselineObserved, 0),
                baselineExpectedDays: max(baselineExpected, 0)
            )
        )
    }

    static func currentV5DayString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// The sole capability catalogue used by the current-v5 runtime. It reads only committed Swift
/// state. A Planner patch can satisfy an operation's evidence precondition, but it can never add
/// an operation to this list or invent a second workflow route.
enum CurrentV5CapabilitySet {
    static func allowedOperations(for session: ReflectionSession) -> [PlannerSemanticOperation] {
        var operations: [PlannerSemanticOperation]
        switch session.protocolStage {
        case .contextualDisclosure:
            operations = isEventDisclosureCoreComplete(
                EffectiveEventDisclosureState(memory: session.semanticMemory)
            )
                ? [.advanceToCardConsent]
                : [.clarifyEvent]
        case .cardConsent:
            operations = [.inviteCardConsent, .acknowledgeCardConsent, .declineCardConsent]
        case .cardReflection:
            if session.cardConnectionUnavailable {
                operations = [.bypassCardConnectionToDirectReflection]
            } else {
                let cardState = EffectiveCardSemanticState(session: session)
                let realityInvitationIsPending =
                    session.semanticMemory.nextPrompt?.purpose == "cardRealityConnection"
                    && [.observation, .development].contains(cardState.substate)
                if realityInvitationIsPending {
                    // The invitation itself is Swift state. Once it has been shown, do not repeat
                    // it merely because the Planner did not populate every Development field.
                    operations = [.continueOpenCardConnection, .offerCardConnectionScaffold]
                } else {
                    switch cardState.substate {
                    case .none:
                        operations = session.cardDisplayState == .displayed
                            ? [.continueCardObservation]
                            : []
                    case .observation:
                        operations = session.semanticMemory.nextPrompt?.purpose == "cardObservation"
                            ? [.continueCardObservation]
                            : [.continueCardDevelopment]
                    case .development:
                        operations = session.semanticMemory.nextPrompt?.purpose == "cardDevelopment"
                            ? [.continueCardDevelopment]
                            : [.continueOpenCardConnection]
                    case .openExploration:
                        operations = [.continueOpenCardConnection,
                                      .bypassCardConnectionToDirectReflection]
                        let state = EffectiveCardSemanticState(session: session)
                        if !state.bridgeScaffoldUsed { operations.append(.offerCardConnectionScaffold) }
                        if state.candidateBridgeEligible {
                            operations.append(.offerCardConnectionCandidate)
                        }
                    case .awaitingCandidateResolution:
                        operations = [.acceptCardConnectionCandidate,
                                      .reviseCardConnectionCandidate,
                                      .rejectCardConnectionCandidate]
                    case .guidance:
                        operations = [.authorizeCardGuidance]
                    }
                }
                if session.semanticMemory.cardRealityConnection?.normalizedConfirmed != nil,
                   !session.cardGuidanceShared {
                    operations = [.authorizeCardGuidance]
                }
            }
        case .directReflection:
            switch session.semanticMemory.reflectionPhase {
            case .exploratory:
                // The current act completes Exploration; the projector alone opens Tender after
                // a grounded link is merged. Keeping one operation here prevents a link-only
                // answer from being reclassified as a premature Tender distinction.
                operations = [.continueExploratoryReflection]
            case .tender:
                let hasStatement = CurrentV5SelfCriticismLineage
                    .canonicalStatement(in: session.semanticMemory)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let lineageNeedsRepair = hasStatement
                    && CurrentV5SelfCriticismLineage.alignedLink(
                        in: session.semanticMemory
                    ) == nil
                if lineageNeedsRepair {
                    // A later exact statement can make a previously saved free-form/Card-ending
                    // relation stale. Repair it in the existing Tender act before exposing later
                    // Reflection operations; do not create a backward stage transition.
                    operations = [.continueTenderReflection]
                } else if hasCommittedTenderUnderstanding(in: session) {
                    // A committed bounded understanding is necessary but does not by itself prove
                    // that Tender is usable for the person. The Planner may revise or clarify that
                    // same understanding, open an evidence-grounded Fierce inquiry, or synthesize
                    // it when the latest user response supports moving on. All three acts keep the
                    // existing phase and operation vocabulary; Swift continues to enforce lineage.
                    operations = [
                        .continueTenderReflection,
                        .continueTenderGroundedFierceReflection,
                        .synthesizeDirectReflection,
                    ]
                } else {
                    // Compatibility for an interrupted saved session that reached the Tender phase
                    // before its first bounded distinction was committed.
                    operations = [.continueTenderReflection]
                }
            case .fierce:
                operations = [.continueTenderGroundedFierceReflection]
                if hasCommittedSynthesisBasis(in: session) {
                    operations.append(.synthesizeDirectReflection)
                }
            case .synthesis:
                if session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding {
                    // The committed synthesis remains negotiable until the person naturally
                    // accepts it. Reuse the same operation for clarification.
                    operations = [.synthesizeDirectReflection, .proposePractice]
                } else if hasCommittedSynthesisBasis(in: session) {
                    // A completed Fierce act has projected the next phase, but has not fabricated
                    // Synthesis content. Require the existing Synthesis act before Action opens.
                    operations = [.synthesizeDirectReflection]
                } else {
                    operations = []
                }
            }
        case .narrativeConfirmation:
            let awaitingNarrativeDecision = session.semanticMemory.nextPrompt?.target == .finalNarrative
            operations = awaitingNarrativeDecision
                ? [.reviseNarrative, .completeConversation]
                : [.confirmNarrative]
            // Compatibility for a saved current-v5 session created before action-first ordering:
            // it may accept the narrative and atomically propose its still-missing action.
            if session.semanticMemory.practiceTransition == nil {
                operations.append(.proposePractice)
            }
        case .optionalAction:
            operations = session.semanticMemory.practiceTransition?.proposal == nil
                ? [.proposePractice]
                : [.resolvePractice]
        case .complete:
            operations = [.completeConversation]
        case .safetySupport:
            operations = [.provideSafetySupport, .completeConversation]
        }
        return Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
    }

    /// Synthesis may integrate only a previously committed grounded reflection. A Planner-created
    /// synthesis frame cannot make its own entry precondition true, and an action idea alone is
    /// not a Tender distinction. The semantic quality of the distinction remains the Planner's
    /// responsibility; Swift checks only phase, typed provenance, and structural presence.
    static func hasCommittedSynthesisBasis(in session: ReflectionSession) -> Bool {
        guard let frame = session.semanticMemory.reflectionFrame,
              frame.hasNonemptyEvidence,
              frame.hasRealityEvidence,
              frame.hasReflectionDelta else {
            return false
        }
        switch session.semanticMemory.reflectionPhase {
        case .tender:
            return frame.mode == .tender
                && frame.action.currentV5ProvidesTenderDistinction
                && frame.fierceEvidence == nil
        case .fierce:
            if frame.mode == .tender {
                // The first Fierce turn opens a user-grounded inquiry while retaining the last
                // committed Tender understanding. If the person does not identify an active need
                // or direction, that Tender understanding can still be synthesized without
                // manufacturing Fierce evidence.
                return frame.action.currentV5ProvidesTenderDistinction
                    && frame.fierceEvidence == nil
            }
            return frame.hasCurrentV5GroundedFierceContribution
        case .synthesis:
            // Fierce completion projects the post-turn Synthesis phase while preserving the
            // complete Fierce frame as its grounded input. Once a synthesis frame exists, this
            // function is no longer an entry-capability check.
            return frame.action != .synthesizeUnderstanding
                && frame.hasCurrentV5GroundedFierceContribution
        case .exploratory:
            return false
        }
    }

    /// Returns whether Tender already has one grounded bounded understanding. This is a structural
    /// capability check, not a claim that the person understands, accepts, or can use it yet.
    static func hasCommittedTenderUnderstanding(in session: ReflectionSession) -> Bool {
        guard session.semanticMemory.reflectionPhase == .tender,
              let frame = session.semanticMemory.reflectionFrame,
              frame.mode == .tender,
              frame.action.currentV5ProvidesTenderDistinction,
              frame.hasNonemptyEvidence,
              frame.hasRealityEvidence,
              frame.hasReflectionDelta,
              frame.fierceEvidence == nil else {
            return false
        }
        return true
    }

}

struct CurrentV5PlannerCorrection: Codable, Equatable, Sendable {
    let rejectedOperation: PlannerSemanticOperation?
    let rejectedDraft: CurrentV5PlannerOutput
    let reason: CurrentV5GateRejectionReason
    let payloadFailure: CurrentV5PayloadFailure?
    let projectionFailure: CurrentV5ProjectionFailure?
    let issue: CurrentV5CorrectionIssue
    let allowedSemanticOperations: [PlannerSemanticOperation]
    let recoveryPolicy: CurrentV5RecoveryPolicy
}

/// The sole actionable description of a rejected current-v5 plan. Diagnostics retain the closed
/// Swift failure enum, while correction receives exactly one writable path and one violation.
/// `requiredConditions` refine that one issue; they never grant another field or operation
/// authority.
struct CurrentV5CorrectionIssue: Codable, Equatable, Sendable {
    let fieldPath: String
    let violation: CurrentV5CorrectionViolation
    let requiredConditions: [CurrentV5RepairRequirement]
}

enum CurrentV5CorrectionViolation: String, Codable, Equatable, Sendable {
    case operationNotAllowed
    case missing
    case empty
    case invalidValue
    case forbidden
    case incomplete
    case sourceMismatch
    case incompatibleState
    case alreadyResolved
}

enum CurrentV5GateRejectionReason: String, Codable, Equatable, Sendable {
    case operationNotAllowed
    case payloadInvalid
    case projectionInvalid
}

/// Closed failures from decoding an operation-owned semantic payload. These values describe only
/// the contract mismatch; they contain no user text and never become session state.
enum CurrentV5PayloadFailure: String, Codable, Equatable, Sendable {
    case malformedSemanticPayload
    case contextualTrackingDecisionInvalid
    case cardObservationEvidenceMissing
    case legacyCardConnectionFieldsPresent
    case cardConnectionOutcomeMissing
    case cardConnectionOutcomeUnexpected
    case cardConnectionOutcomeKindMismatch
    case cardConnectionIncomplete
    case cardConnectionSourceMismatch
}

/// Closed structural diagnostics for the one current-v5 correction. They contain no user text and
/// never become workflow state; the backend maps them to a concise repair contract.
enum CurrentV5ProjectionFailure: String, Codable, Equatable, Sendable {
    case sourceStageMismatch
    case responseFocusMissing
    case eventAlreadyComplete
    case eventCoreIncomplete
    case cardNotDisplayed
    case cardObservationMissing
    case cardSubstateMismatch
    case cardConnectionDifficultyMissing
    case cardScaffoldAlreadyUsed
    case cardCandidateNotEligible
    case cardCandidateMissing
    case cardCandidateIncomplete
    case cardCandidateAlreadyPending
    case cardConnectionAlreadyExists
    case cardConnectionMissing
    case cardConnectionSourceInvalid
    case cardConnectionUnavailable
    case cardBypassNotAuthorized
    case cardGuidanceAlreadyShared
    case legacyOperationUnavailable
    case reflectionPhaseMismatch
    case reflectionProgressionInvalid
    case unexpectedReflectionFrame
    case tenderFrameMissing
    case tenderModeInvalid
    case tenderActionIncompatible
    case tenderEvidenceMissing
    case tenderDeltaMissing
    case unexpectedFierceEvidence
    case fierceFrameIncomplete
    case synthesisFrameMissing
    case synthesisActionInvalid
    case synthesisDeltaMissing
    case synthesisModeInvalid
    case synthesisEvidenceInvalid
    case rejectedInterpretationReused
    case practiceProposalMissing
    case practiceProposalIncomplete
    case practiceEvidenceInvalid
    case activePracticeMissing
    case practiceResolutionMissing
    case finalNarrativeMissing
    case finalNarrativeRevisionMissing
    case activeNarrativeConfirmationMissing
    case structuralPreconditionFailed
}

enum CurrentV5RepairRequirement: String, Codable, Equatable, Sendable {
    case remainInCurrentPhase
    case omitReflectionFrame
    case provideResponseFocus
    case completeEventCore
    case followCardEvidenceProgression
    case preserveCurrentCardSubstate
    case provideConnectionDifficultyOutcome
    case provideCompleteCardCandidate
    case provideCompleteCardConnection
    case useRequiredCardConnectionSource
    case resolveActiveCardCandidate
    case omitLegacyCardConnectionFields
    case omitCardConnectionOutcome
    case useMatchingCardConnectionOutcome
    case provideTenderFrame
    case useTenderMode
    case useTenderCompatibleAction
    case citeGroundedUserEvidence
    case provideConcreteReflectionDelta
    case omitFierceEvidence
    case provideCompleteFierceEvidence
    case provideSynthesisFrame
    case useSynthesisAction
    case useSynthesisMode
    case preserveCommittedReflectionLineage
    case avoidRejectedInterpretation
    case provideCompletePracticeProposal
    case resolveActivePractice
    case provideFinalNarrative
    case provideRevisedFinalNarrative
    case resolveActiveNarrative
    case satisfyTypedPreconditions
    case provideContextualTrackingDecision
}

enum CurrentV5RecoveryPolicy: String, Codable, Equatable, Sendable {
    case repairSameOperation
    case remainInCurrentPhase
}

enum CurrentV5WriterReflectionRealization: String, Codable, Equatable, Sendable {
    case standard
    case establishTenderUnderstanding
    case openFierceInquiry
    case askFierceClarification
    case bridgeToSynthesis
}

struct CurrentV5WriterDirective: Codable, Equatable, Sendable {
    let semanticOperation: PlannerSemanticOperation
    let responseFocus: String?
    /// Writer realizes an already-authorized semantic result. It cannot infer this distinction
    /// from the shared Fierce operation name or reopen a completed progression.
    let reflectionRealization: CurrentV5WriterReflectionRealization
    let mayAskQuestion: Bool
    let sourceStage: ReflectionProtocolStage
    let destinationStage: ReflectionProtocolStage
    let nextPrompt: TurnNextPrompt
    let localAction: TurnLocalActionKind
    let memoryUpdate: TurnSemanticMemoryUpdate
    let contextualTrackingMetricRef: ContextualTrackingMetricIdentity?
    /// Swift-scoped factual slice for the selected metric. For a dated episode this contains
    /// only the event-day value, or adjacent values when the event day is unobserved. Writer must
    /// not return to the complete weekly profile and choose a different date.
    let contextualTrackingMetricEvidence: LLMTurnTemporalMetricProfile?
    let rewriteReason: String?

    init(
        authorized: CurrentV5AuthorizedTurn,
        rewriteReason: String? = nil
    ) {
        semanticOperation = authorized.operation
        reflectionRealization = switch authorized.reflectionProgressionMeaning {
        case .completeExploration:
            .establishTenderUnderstanding
        case .inspectReality:
            .openFierceInquiry
        case .clarifyFierce:
            .askFierceClarification
        case .completeFierce:
            .bridgeToSynthesis
        default:
            .standard
        }
        mayAskQuestion = switch reflectionRealization {
        case .establishTenderUnderstanding, .openFierceInquiry, .askFierceClarification:
            true
        case .bridgeToSynthesis:
            false
        case .standard:
            [.openQuestion, .confirmationRequest].contains(
                authorized.projectedPlan.nextPrompt.kind
            )
        }
        // These two prompts must be shaped only by their operation contract and the person's
        // grounded scene. A free-form Planner focus can otherwise locate the image tension or
        // preselect a Card-to-reality mapping before Writer asks the open question.
        switch authorized.operation {
        case .continueCardDevelopment, .inviteRealityConnection,
             .advanceToCardConsent, .inviteCardConsent:
            responseFocus = nil
        case .clarifyEvent where authorized.projectedPlan.requestedStage == .cardConsent:
            // Card consent is always an invitation to a still-unknown random card. Event wording
            // must not survive as a fabricated card theme or preview.
            responseFocus = nil
        case .continueCardObservation
            where ["cardDevelopment", "cardRealityConnection"].contains(
                authorized.projectedPlan.nextPrompt.purpose ?? ""
            ):
            responseFocus = nil
        case .continueTenderGroundedFierceReflection
            where authorized.projectedPlan.nextPrompt.purpose == "synthesisReflection":
            // Once the latest answer completes Fierce, no Planner-authored question or action
            // wording may survive into the bridge toward Synthesis.
            responseFocus = nil
        case .synthesizeDirectReflection, .resolvePractice, .completeConversation:
            // These operations already carry their complete semantic content in the projected
            // update. A free-form focus would create a second owner for advice, confirmation, or
            // closing content and can replay the previous stage's task.
            responseFocus = nil
        default:
            responseFocus = authorized.responseFocus
        }
        sourceStage = authorized.projectedPlan.sourceStage
        destinationStage = authorized.projectedPlan.requestedStage
        nextPrompt = authorized.projectedPlan.nextPrompt
        localAction = authorized.projectedPlan.localAction.kind
        switch authorized.operation {
        case .resolvePractice:
            // The accepted/revised Action transaction is already resolved. The Writer receives
            // only the final narrative it must present, not the proposal it must never negotiate
            // again.
            memoryUpdate = TurnSemanticMemoryUpdate(
                finalNarrative: authorized.projectedPlan.memoryUpdate.finalNarrative
            )
        case .completeConversation:
            // Completion is a short closure, not another opportunity to replay narrative or
            // practice content.
            memoryUpdate = TurnSemanticMemoryUpdate()
        default:
            memoryUpdate = authorized.projectedPlan.memoryUpdate
        }
        contextualTrackingMetricRef = authorized.contextualTrackingMetricRef
        contextualTrackingMetricEvidence = authorized.contextualTrackingMetricEvidence
        self.rewriteReason = rewriteReason
    }
}

struct CurrentV5WriterOutput: Codable, Equatable, Sendable {
    let reply: String
}

struct CurrentV5AuthorizedTurn: Equatable, Sendable {
    let operation: PlannerSemanticOperation
    let responseFocus: String?
    let reflectionProgressionMeaning: CurrentV5ReflectionProgressionMeaning?
    let projectedPlan: ProjectedExecutableTurnPlan
    let contextualTrackingMetricRef: ContextualTrackingMetricIdentity?
    let contextualTrackingMetricEvidence: LLMTurnTemporalMetricProfile?
}

/// The bounded correction path may carry forward user-grounded evidence that Swift has already
/// validated, but it never commits a frame, narrative, action, or phase from a rejected draft.
/// Fully authorized turns do not use this allowlist: their complete canonical projection is the
/// single atomic state transaction before Writer generation.
private func currentV5DurableUserEvidence(
    from source: TurnSemanticMemoryUpdate,
    operation: PlannerSemanticOperation,
    includeResolvedTransactions: Bool
) -> TurnSemanticMemoryUpdate {
    // A newly added semantic field is not carried through correction by accident: it must first
    // be classified as independently user-grounded evidence here.
    var update = TurnSemanticMemoryUpdate(
        answeredQuestionPurposes: source.answeredQuestionPurposes,
        receivedDisclosureQuestionPurposes: source.receivedDisclosureQuestionPurposes,
        eventDisclosureOutcome: source.eventDisclosureOutcome,
        selfCriticismStatus: source.selfCriticismStatus,
        selfCriticalStatement: source.selfCriticalStatement,
        selfCriticismLink: source.selfCriticismLink,
        episodeStructure: source.episodeStructure,
        contextRelationship: source.contextRelationship,
        trackingAssessments: source.trackingAssessments,
        cardObservationEvidence: source.cardObservationEvidence,
        cardDevelopmentEvidence: source.cardDevelopmentEvidence,
        invalidatedInterpretations: source.invalidatedInterpretations
    )

    let resolvesCardConnection: Set<PlannerSemanticOperation> = [
        .continueOpenCardConnection,
        .offerCardConnectionScaffold,
        .establishUserAuthoredCardConnection,
        .acceptCardConnectionCandidate,
        .reviseCardConnectionCandidate,
    ]
    if includeResolvedTransactions, resolvesCardConnection.contains(operation) {
        update.cardRealityConnection = source.cardRealityConnection
    }

    let resolvesPendingCandidate: Set<PlannerSemanticOperation> = [
        .acceptCardConnectionCandidate,
        .reviseCardConnectionCandidate,
        .rejectCardConnectionCandidate,
    ]
    if includeResolvedTransactions, resolvesPendingCandidate.contains(operation) {
        update.clearPendingCardRealityConnection = source.clearPendingCardRealityConnection
        update.candidateBridgeResolvedAt = source.candidateBridgeResolvedAt
    }

    let recordsConnectionOutcome: Set<PlannerSemanticOperation> = [
        .continueOpenCardConnection,
        .offerCardConnectionScaffold,
        .establishUserAuthoredCardConnection,
        .acceptCardConnectionCandidate,
        .reviseCardConnectionCandidate,
        .rejectCardConnectionCandidate,
    ]
    if !includeResolvedTransactions || !recordsConnectionOutcome.contains(operation) {
        update.cardConnectionOutcome = nil
    } else {
        update.cardConnectionOutcome = source.cardConnectionOutcome
    }

    // Practice resolution never passes through a rejected-draft carry-forward. On an authorized
    // turn it is committed only as part of the full canonical Action→Final Narrative transaction.
    return update
}

enum CurrentV5CoreError: Error, Equatable {
    case operationNotAllowed(
        PlannerSemanticOperation,
        allowedSemanticOperations: [PlannerSemanticOperation]
    )
    case payloadInvalid(failure: CurrentV5PayloadFailure)
    case projectionInvalid(
        operation: PlannerSemanticOperation,
        failure: CurrentV5ProjectionFailure
    )
    case emptyWriterReply
}

protocol CurrentV5CoreTurnControlling: Sendable {
    func plan(_ request: CurrentV5TurnRequest) async throws -> CurrentV5PlannerOutput
    func write(
        request: CurrentV5TurnRequest,
        directive: CurrentV5WriterDirective
    ) async throws -> CurrentV5WriterOutput
}

/// Privacy-safe transport boundary errors. They carry no model body or reflection text and do not
/// participate in workflow state; the ViewModel records only which boundary failed.
enum CurrentV5RemoteContractError: Error {
    case plannerContractInvalid
    case writerContractInvalid
}

enum CurrentV5ServerPrompt {
    static let version = "turn-v5-core-server-v106"
}

private struct CurrentV5PlannerPayload: Encodable {
    let request: CurrentV5TurnRequest
}

private struct CurrentV5WriterPayload: Encodable {
    let request: CurrentV5TurnRequest
    let directive: CurrentV5WriterDirective
}

struct RemoteCurrentV5CoreTurnController: CurrentV5CoreTurnControlling {
    func plan(_ request: CurrentV5TurnRequest) async throws -> CurrentV5PlannerOutput {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: "planner",
            promptVersion: CurrentV5ServerPrompt.version,
            payload: CurrentV5PlannerPayload(request: request),
            maxTokens: 1_300,
            temperature: 0.28
        )
        guard let data = content.data(using: .utf8) else {
            throw LLMError.malformedResponse
        }
        do {
            return try decodeCurrentV5PlannerWireOutput(
                data,
                allowedSemanticOperations: request.allowedSemanticOperations,
                canonicalSelfCriticalStatement: request.semanticMemory.selfCriticalStatement,
                pendingRealityCandidate: request.reflectionMode == .tender
                    ? request.semanticMemory.pendingRealityCandidate
                    : nil
            )
        } catch {
            if error is CurrentV5RemoteContractError { throw error }
            throw CurrentV5RemoteContractError.plannerContractInvalid
        }
    }

    func write(
        request: CurrentV5TurnRequest,
        directive: CurrentV5WriterDirective
    ) async throws -> CurrentV5WriterOutput {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: "writer",
            promptVersion: CurrentV5ServerPrompt.version,
            payload: CurrentV5WriterPayload(
                request: request.scopedForWriter(operation: directive.semanticOperation),
                directive: directive
            ),
            maxTokens: 700,
            temperature: directive.rewriteReason == nil ? 0.42 : 0.24
        )
        guard let data = content.data(using: .utf8) else {
            throw LLMError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(CurrentV5WriterOutput.self, from: data)
        } catch {
            throw CurrentV5RemoteContractError.writerContractInvalid
        }
    }
}

/// The sole current-v5 execution gate. It validates what this turn did against the committed
/// pre-turn state. Only after that succeeds may the deterministic projector derive where the
/// merged candidate state starts the next turn. Completing a phase never renames the current act.
struct CurrentV5SwiftTurnGate: Sendable {
    private let protocolController: ReflectionProtocolController

    init(protocolController: ReflectionProtocolController) {
        self.protocolController = protocolController
    }

    func authorize(
        _ output: CurrentV5PlannerOutput,
        for session: ReflectionSession,
        allowedSemanticOperations: [PlannerSemanticOperation]
    ) throws -> CurrentV5AuthorizedTurn {
        protocolController.recordExecutionAudit(.semanticMapper)
        let operation = currentActOperation(
            for: output,
            allowedSemanticOperations: allowedSemanticOperations
        )
        guard allowedSemanticOperations.contains(operation) else {
            throw CurrentV5CoreError.operationNotAllowed(
                output.semanticOperation,
                allowedSemanticOperations: allowedSemanticOperations
            )
        }
        let evaluation = evaluate(
            operation: operation,
            output: output,
            session: session
        )
        guard let authorized = evaluation.authorized else {
            throw evaluation.failure ?? CurrentV5CoreError.payloadInvalid(
                failure: .malformedSemanticPayload
            )
        }

        protocolController.recordExecutionAudit(.projector)

        let trackingReference = output.semanticEvidencePatch
            .contextualTrackingDecision?.preferredMetricReference
        let trackingEvidence = trackingReference.flatMap {
            contextualTrackingEvidence(for: $0, in: session)
        }
        // A selected metric may reach Writer only when Swift can compile the exact factual slice
        // that selection names. This is temporal/provenance validation, not a relevance decision.
        if trackingReference != nil, trackingEvidence == nil {
            throw CurrentV5CoreError.payloadInvalid(
                failure: .contextualTrackingDecisionInvalid
            )
        }
        return CurrentV5AuthorizedTurn(
            operation: authorized.operation,
            responseFocus: authorized.responseFocus,
            reflectionProgressionMeaning: output.reflectionProgressionDecision?.meaning,
            projectedPlan: authorized.projected,
            contextualTrackingMetricRef: trackingReference,
            contextualTrackingMetricEvidence: trackingEvidence
        )
    }

    /// Last-resort continuity for a parseable Reflection response whose semantic conclusion still
    /// fails after the one bounded correction. Swift does not invent a link, interpretation,
    /// Fierce direction, Synthesis, or phase transition. It authorizes only the canonical
    /// non-advancing inquiry for the already committed phase, so protocol incompleteness cannot
    /// become a user-visible technical interruption.
    func authorizeCurrentReflectionContinuation(
        for session: ReflectionSession,
        allowedSemanticOperations: [PlannerSemanticOperation]
    ) throws -> CurrentV5AuthorizedTurn {
        guard session.protocolStage == .directReflection else {
            throw CurrentV5CoreError.payloadInvalid(
                failure: .malformedSemanticPayload
            )
        }
        let meaning: CurrentV5ReflectionProgressionMeaning = switch session.semanticMemory.reflectionPhase {
        case .exploratory: .continueExploration
        case .tender: .clarifyTender
        case .fierce: .clarifyFierce
        case .synthesis: .clarifySynthesis
        }
        let operation = meaning.compiledOperation
        guard allowedSemanticOperations.contains(operation) else {
            throw CurrentV5CoreError.operationNotAllowed(
                operation,
                allowedSemanticOperations: allowedSemanticOperations
            )
        }
        let output = CurrentV5PlannerOutput(
            semanticOperation: operation,
            semanticEvidencePatch: CurrentV5SemanticEvidencePatch(),
            reflectionProgressionDecision: CurrentV5ReflectionProgressionDecision(
                meaning: meaning,
                candidateRef: nil
            ),
            phaseOutcomeContractApplied: true
        )
        return try authorize(
            output,
            for: session,
            allowedSemanticOperations: allowedSemanticOperations
        )
    }

    /// Compile the one factual temporal slice Writer is permitted to verbalize. Relevance remains
    /// the Planner's decision; Swift only prevents a selected metric from drifting to an unrelated
    /// day after authorization.
    private func contextualTrackingEvidence(
        for reference: ContextualTrackingMetricIdentity,
        in session: ReflectionSession
    ) -> LLMTurnTemporalMetricProfile? {
        guard let metric = LLMTurnContextualTrackingProfile.currentV5Profiles(in: session)
            .first(where: { $0.profileID == reference.profileID })?
            .metrics.first(where: { $0.metric == reference.metric }) else {
            return nil
        }
        guard session.eventDateIsUserSpecified else { return metric }

        let anchor = TrackingMetric.currentV5DayString(session.context.eventDate)
        let exact = metric.recentDaily.filter { $0.date == anchor }
        let scopedPoints: [LLMTurnTemporalDataPoint]
        if !exact.isEmpty {
            scopedPoints = exact
        } else {
            let calendar = Calendar.current
            let anchorDay = calendar.startOfDay(for: session.context.eventDate)
            scopedPoints = metric.recentDaily.filter { point in
                let parts = point.date.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3,
                      let date = calendar.date(
                        from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
                      ) else { return false }
                let distance = abs(
                    calendar.dateComponents([.day], from: anchorDay, to: date).day ?? Int.max
                )
                return distance == 1
            }
        }
        guard !scopedPoints.isEmpty else { return nil }
        let values = scopedPoints.map(\.value)
        return LLMTurnTemporalMetricProfile(
            metric: metric.metric,
            unit: metric.unit,
            recentDaily: scopedPoints,
            recentMedian: TrackingStatistics.median(values),
            recentTotal: metric.recentTotal == nil ? nil : values.reduce(0, +),
            recentRecordCount: metric.recentRecordCount,
            baselineMedian: metric.baselineMedian,
            coverage: LLMTurnTemporalCoverage(
                recentObservedDays: scopedPoints.count,
                recentExpectedDays: scopedPoints.count,
                recentSampleCount: scopedPoints.reduce(0) { $0 + $1.sampleCount },
                baselineObservedDays: metric.coverage.baselineObservedDays,
                baselineExpectedDays: metric.coverage.baselineExpectedDays
            )
        )
    }

    /// Resolve only the current act under committed pre-turn capability. Tagged payload metadata
    /// has no authority. Legacy transition-like names are decode aliases for the neutral current
    /// act and candidate completion is evaluated only after semantic evidence is merged.
    private func currentActOperation(
        for output: CurrentV5PlannerOutput,
        allowedSemanticOperations: [PlannerSemanticOperation]
    ) -> PlannerSemanticOperation {
        if let progression = output.reflectionProgressionDecision {
            return progression.meaning.compiledOperation
        }
        if allowedSemanticOperations.contains(output.semanticOperation) {
            return output.semanticOperation
        }
        if output.semanticOperation == .establishUserAuthoredCardConnection,
           allowedSemanticOperations.contains(.continueOpenCardConnection) {
            return .continueOpenCardConnection
        }
        if output.semanticOperation == .advanceToCardConsent,
           allowedSemanticOperations.contains(.clarifyEvent) {
            return .clarifyEvent
        }
        if allowedSemanticOperations.count == 1,
           let onlyOperation = allowedSemanticOperations.first {
            return onlyOperation
        }
        return output.semanticOperation
    }

    private struct OperationEvaluation {
        struct Authorized {
            let operation: PlannerSemanticOperation
            let responseFocus: String
            let projected: ProjectedExecutableTurnPlan
        }

        let operation: PlannerSemanticOperation
        let authorized: Authorized?
        let failure: CurrentV5CoreError?
    }

    private struct ResolvedReflectionProgression {
        let meaning: CurrentV5ReflectionProgressionMeaning
        let candidateReference: String?
        let candidateContent: String?
        let candidateMeaning: TurnRealityCandidateMeaning?
        let selfCriticismLink: String?
        let reflectionDelta: String?
        let fierceDirection: TurnFierceDirection?
        let fierceEvidenceBasis: [String]

        init(
            meaning: CurrentV5ReflectionProgressionMeaning,
            candidateReference: String?,
            candidateContent: String?,
            candidateMeaning: TurnRealityCandidateMeaning? = nil,
            selfCriticismLink: String? = nil,
            reflectionDelta: String?,
            fierceDirection: TurnFierceDirection?,
            fierceEvidenceBasis: [String]
        ) {
            self.meaning = meaning
            self.candidateReference = candidateReference
            self.candidateContent = candidateContent
            self.candidateMeaning = candidateMeaning
            self.selfCriticismLink = selfCriticismLink
            self.reflectionDelta = reflectionDelta
            self.fierceDirection = fierceDirection
            self.fierceEvidenceBasis = fierceEvidenceBasis
        }
    }

    private func latestUnansweredUserContent(in session: ReflectionSession) -> String? {
        guard let message = session.messages.last(where: { $0.role == .user }) else {
            return nil
        }
        let alreadyAnswered = session.messages.contains {
            $0.role == .assistant && $0.replyToMessageID == message.id
        }
        guard !alreadyAnswered else { return nil }
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    /// Validate Planner-owned progression meaning against authoritative pre-turn Reflection state.
    /// This layer owns semantic permission. Writer focus compilation below only realizes a result
    /// that has already passed here and cannot reject or reinterpret progression.
    private func resolvedReflectionProgression(
        output: CurrentV5PlannerOutput,
        operation: PlannerSemanticOperation,
        session: ReflectionSession
    ) throws -> ResolvedReflectionProgression? {
        let resolvesPresentedContextCue =
            session.semanticMemory.nextPrompt?.purpose == "contextRelationship"
            && output.semanticEvidencePatch.memoryUpdate.contextRelationship != nil
        let hasCommittedTenderBoundary =
            session.protocolStage == .directReflection
            && session.semanticMemory.reflectionPhase == .tender
            && session.semanticMemory.reflectionFrame != nil
            && !resolvesPresentedContextCue
        let hasActiveFierceBoundary =
            session.protocolStage == .directReflection
            && session.semanticMemory.reflectionPhase == .fierce
            && session.semanticMemory.reflectionFrame != nil
            && !resolvesPresentedContextCue
        let hasExplorationBoundary =
            session.protocolStage == .directReflection
            && session.semanticMemory.reflectionPhase == .exploratory
            && !resolvesPresentedContextCue
        let hasSynthesisBoundary =
            session.protocolStage == .directReflection
            && session.semanticMemory.reflectionPhase == .synthesis
            && !resolvesPresentedContextCue
        let requiresDecision = output.phaseOutcomeContractApplied
            && (hasExplorationBoundary
                || hasCommittedTenderBoundary
                || hasActiveFierceBoundary
                || hasSynthesisBoundary)

        func invalid() -> CurrentV5CoreError {
            .projectionInvalid(
                operation: operation,
                failure: .reflectionProgressionInvalid
            )
        }
        guard let progression = output.reflectionProgressionDecision else {
            guard !requiresDecision else { throw invalid() }
            return nil
        }
        guard operation == progression.meaning.compiledOperation else {
            throw invalid()
        }

        let phase = session.semanticMemory.reflectionPhase
        let meaningIsAllowed: Bool = switch phase {
        case .exploratory:
            hasExplorationBoundary
                && [.continueExploration, .completeExploration].contains(
                    progression.meaning
                )
        case .tender:
            hasCommittedTenderBoundary
                && [.reviseTender, .clarifyTender, .inspectReality, .synthesize].contains(
                    progression.meaning
                )
        case .fierce:
            hasActiveFierceBoundary
                && [.clarifyFierce, .completeFierce, .synthesize].contains(
                    progression.meaning
                )
        case .synthesis:
            hasSynthesisBoundary
                && [.synthesize, .clarifySynthesis, .acceptSynthesis].contains(
                    progression.meaning
                )
        }
        guard meaningIsAllowed else { throw invalid() }

        let candidates = CurrentV5GroundedRealityCandidate.projected(
            from: session.semanticMemory
        )
        let candidateEvidence = CurrentV5GroundedRealityCandidate.projected(
            from: session.semanticMemory,
            applying: output.semanticEvidencePatch.memoryUpdate
        ).filter { candidate in
            // A current-turn Reflection conclusion cannot establish its own provenance. Newly
            // supplied episode/context fields and committed user-evidence lineage remain valid;
            // a new uncommitted reflectionFrame and a non-user-authored Card mapping do not.
            let committedReflectionEvidence = candidate.source != .reflectionEvidence
                || candidates.contains(where: { $0.id == candidate.id })
            let userAuthoredCardEvidence = candidate.source != .cardRealityConnection
                || [.userAuthored, .userRevised].contains(candidate.cardAuthorship)
            return committedReflectionEvidence && userAuthoredCardEvidence
        }
        switch progression.meaning {
        case .continueExploration:
            guard progression.reflectionDelta == nil,
                  progression.fierceDirection == nil else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: nil,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .completeExploration:
            guard let delta = progression.reflectionDelta?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !delta.isEmpty,
                  progression.fierceDirection == nil,
                  let link = progression.selfCriticismLink,
                  CurrentV5SelfCriticismLineage.alignedLink(
                    statement: output.semanticEvidencePatch.memoryUpdate.selfCriticalStatement
                        ?? session.semanticMemory.selfCriticalStatement,
                    link: link
                  ) != nil else {
                throw invalid()
            }
            let selectedCandidate: CurrentV5GroundedRealityCandidate?
            if let reference = progression.candidateRef {
                // Candidate selection is optional enrichment. An unknown, stale, or otherwise
                // ungrounded reference cannot block the canonical Exploration transaction once
                // the self-criticism link and Tender understanding are valid.
                selectedCandidate = progression.candidateMeaning.flatMap { _ in
                    candidateEvidence.first(where: { $0.id == reference })
                }
            } else {
                selectedCandidate = nil
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: selectedCandidate?.id,
                candidateContent: selectedCandidate?.content,
                candidateMeaning: selectedCandidate == nil
                    ? nil
                    : progression.candidateMeaning,
                selfCriticismLink: link,
                reflectionDelta: delta,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .reviseTender:
            guard progression.fierceDirection == nil else { throw invalid() }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: progression.reflectionDelta,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .clarifyTender:
            guard progression.reflectionDelta == nil,
                  progression.fierceDirection == nil else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: nil,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .inspectReality:
            guard progression.fierceDirection == nil,
                  let reference = progression.candidateRef,
                  let candidate = candidates.first(where: { $0.id == reference }) else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: candidate.id,
                candidateContent: candidate.content,
                candidateMeaning: progression.candidateMeaning,
                // tenderRevised may atomically preserve the person's material correction while
                // the same accepted outcome opens a grounded Fierce inquiry. An accepted,
                // unchanged Tender carries no delta here.
                reflectionDelta: progression.reflectionDelta,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .clarifyFierce:
            guard progression.reflectionDelta == nil,
                  progression.fierceDirection == nil,
                  let reference = session.semanticMemory.nextPrompt?.referenceID,
                  let candidate = candidates.first(where: { $0.id == reference }) else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: candidate.id,
                candidateContent: candidate.content,
                reflectionDelta: nil,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .completeFierce:
            guard let delta = progression.reflectionDelta?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !delta.isEmpty,
                  let direction = progression.fierceDirection,
                  let reference = session.semanticMemory.nextPrompt?.referenceID,
                  let candidate = candidates.first(where: { $0.id == reference }),
                  let latestAnswer = latestUnansweredUserContent(in: session) else {
                throw invalid()
            }
            // The active candidate anchors the inquiry but is not a lifetime evidence silo.
            // Completion may use any already committed user-authored reality material plus sparse
            // evidence from this turn, so a previously stated repair/protect/change direction
            // does not have to be repeated in the person's final answer.
            let evidence = ([candidate.content, latestAnswer] + candidateEvidence.map(\.content))
                .reduce(into: [String]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: candidate.id,
                candidateContent: candidate.content,
                reflectionDelta: delta,
                fierceDirection: direction,
                fierceEvidenceBasis: evidence
            )

        case .synthesize:
            guard progression.fierceDirection == nil else { throw invalid() }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: progression.reflectionDelta,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .clarifySynthesis:
            guard progression.reflectionDelta == nil,
                  progression.fierceDirection == nil,
                  session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: nil,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )

        case .acceptSynthesis:
            guard progression.reflectionDelta == nil,
                  progression.fierceDirection == nil,
                  session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding else {
                throw invalid()
            }
            return ResolvedReflectionProgression(
                meaning: progression.meaning,
                candidateReference: nil,
                candidateContent: nil,
                reflectionDelta: nil,
                fierceDirection: nil,
                fierceEvidenceBasis: []
            )
        }
    }

    /// Compile the one atomic Reflection progression envelope before semantic normalization. Direct
    /// test/legacy callers may still supply the former separate reflection contribution when the
    /// colocated delta is absent. Candidate identity and evidence never come from duplicate Planner
    /// metadata at an active Fierce boundary.
    private func atomicProgressionPatch(
        for output: CurrentV5PlannerOutput,
        resolved progression: ResolvedReflectionProgression?
    ) -> CurrentV5SemanticEvidencePatch {
        var patch = output.semanticEvidencePatch
        guard let progression else { return patch }
        switch progression.meaning {
        case .continueExploration:
            patch.memoryUpdate.selfCriticismLink = nil
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = nil
        case .clarifyTender, .clarifyFierce, .clarifySynthesis, .acceptSynthesis:
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = nil
        case .completeExploration:
            patch.memoryUpdate.selfCriticismLink = progression.selfCriticismLink
            if let reference = progression.candidateReference,
               let meaning = progression.candidateMeaning {
                patch.memoryUpdate.pendingRealityCandidate = .init(
                    reference: reference,
                    meaning: meaning
                )
            }
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = CurrentV5ReflectionContribution(
                reflectionDelta: progression.reflectionDelta
            )
        case .inspectReality:
            patch.memoryUpdate.clearPendingRealityCandidate = true
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = progression.reflectionDelta.map {
                CurrentV5ReflectionContribution(reflectionDelta: $0)
            }
        case .completeFierce:
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = CurrentV5ReflectionContribution(
                evidenceBasis: progression.fierceEvidenceBasis,
                reflectionDelta: progression.reflectionDelta,
                fierceEvidence: CurrentV5FierceContribution(
                    behavior: nil,
                    impact: nil,
                    direction: progression.fierceDirection
                )
            )
        case .reviseTender:
            guard progression.reflectionDelta != nil else {
                // Decode-only compatibility for the former separated decision/frame contract.
                return patch
            }
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = CurrentV5ReflectionContribution(
                reflectionDelta: progression.reflectionDelta
            )
        case .synthesize:
            patch.memoryUpdate.clearPendingRealityCandidate = true
            guard progression.reflectionDelta != nil else {
                // Decode-only compatibility for the former separated decision/frame contract.
                return patch
            }
            patch.memoryUpdate.reflectionFrame = nil
            patch.reflectionContribution = CurrentV5ReflectionContribution(
                reflectionDelta: progression.reflectionDelta
            )
        }
        return patch
    }

    /// Validate one immutable Planner act under the committed pre-turn capability. The projector
    /// may derive a different post-turn phase, but the act itself is never relabeled and its
    /// semantic payload is never reinterpreted as the next phase's content.
    private func evaluate(
        operation: PlannerSemanticOperation,
        output: CurrentV5PlannerOutput,
        session: ReflectionSession
    ) -> OperationEvaluation {
        do {
            let progression = try resolvedReflectionProgression(
                output: output,
                operation: operation,
                session: session
            )
            let semanticPatch = atomicProgressionPatch(
                for: output,
                resolved: progression
            )
            let update = try normalizedEvidence(
                semanticPatch,
                for: operation,
                in: session
            )
            let responseFocus = compiledResponseFocus(
                output: output,
                progression: progression
            )
            let projected = try CurrentV5CanonicalProjector().project(
                operation: operation,
                memoryUpdate: update,
                responseFocus: responseFocus,
                hasReflectionContribution: operation == .continueExploratoryReflection
                    ? progression?.meaning == .completeExploration
                        && update.reflectionFrame != nil
                    : semanticPatch.reflectionContribution?.hasSemanticContent == true
                        || semanticPatch.memoryUpdate.reflectionFrame != nil,
                reflectionProgressionMeaning: progression?.meaning,
                inspectedRealityCandidateReference: {
                    if progression?.meaning == .inspectReality {
                        return progression?.candidateReference
                    }
                    if session.semanticMemory.reflectionPhase == .fierce {
                        return progression?.candidateReference
                            ?? session.semanticMemory.nextPrompt?.referenceID
                    }
                    return nil
                }(),
                session: session
            )
            return OperationEvaluation(
                operation: operation,
                authorized: .init(
                    operation: operation,
                    responseFocus: responseFocus,
                    projected: projected
                ),
                failure: nil
            )
        } catch let error as CurrentV5CoreError {
            return OperationEvaluation(operation: operation, authorized: nil, failure: error)
        } catch {
            return OperationEvaluation(
                operation: operation,
                authorized: nil,
                failure: .payloadInvalid(failure: .malformedSemanticPayload)
            )
        }
    }

    private func compiledResponseFocus(
        output: CurrentV5PlannerOutput,
        progression: ResolvedReflectionProgression?
    ) -> String {
        guard let progression else { return output.responseFocus }
        let supplied = output.responseFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        switch progression.meaning {
        case .continueExploration:
            return supplied.isEmpty
                ? "clarify_self_criticism_attribution_relation"
                : supplied
        case .reviseTender, .synthesize:
            return output.responseFocus
        case .clarifyTender:
            return supplied.isEmpty
                ? "clarify_current_bounded_tender_understanding"
                : supplied
        case .clarifySynthesis:
            return supplied.isEmpty
                ? "continue_from_synthesis_or_correct_it"
                : supplied
        case .completeExploration, .acceptSynthesis:
            return ""
        case .inspectReality:
            // The exact canonical reality candidate, rather than a second free-form Planner
            // instruction, is the only Writer focus for opening Fierce.
            return progression.candidateContent ?? ""
        case .clarifyFierce:
            return supplied.isEmpty
                ? progression.candidateContent
                    ?? "clarify_current_grounded_reality_direction"
                : supplied
        case .completeFierce:
            // A completed direction has no remaining Writer question or free-form task. The
            // projected synthesis prompt alone defines the visible transition.
            return ""
        }
    }

    /// Preserve separately valid user evidence when the current act needs one correction.
    /// This never changes the act or phase; correction is evaluated with the durable evidence
    /// contributed by the same user turn instead of losing it and rereading an older snapshot.
    func validatedDurableEvidenceForCorrection(
        _ output: CurrentV5PlannerOutput,
        for session: ReflectionSession,
        initiallyAllowedOperations: [PlannerSemanticOperation]
    ) throws -> TurnSemanticMemoryUpdate {
        let operation = currentActOperation(
            for: output,
            allowedSemanticOperations: initiallyAllowedOperations
        )
        guard initiallyAllowedOperations.contains(operation) else {
            throw CurrentV5CoreError.operationNotAllowed(
                operation,
                allowedSemanticOperations: initiallyAllowedOperations
            )
        }
        let normalized = try normalizedEvidence(
            output.semanticEvidencePatch,
            for: operation,
            in: session
        )
        return currentV5DurableUserEvidence(
            from: normalized,
            operation: operation,
            includeResolvedTransactions: false
        )
    }

    /// Normalizes only operation-owned evidence. This is not a second Planner and never selects a
    /// replacement operation. In particular, legacy scalar Card fields cannot re-enter v5.
    private func normalizedEvidence(
        _ patch: CurrentV5SemanticEvidencePatch,
        for operation: PlannerSemanticOperation,
        in session: ReflectionSession
    ) throws -> TurnSemanticMemoryUpdate {
        var update = patch.memoryUpdate
        // This is an internal presentation signal derived from the transient typed selection
        // below. Direct Planner output cannot create a second writable path for the same decision.
        update.contextCueOffered = nil
        // Reflection phase is projected from the authorized operation below. A Planner-supplied
        // value can never become a second transition authority.
        update.reflectionPhase = nil
        // Planner owns the exact grounded statement, not the redundant presence summary. Keeping
        // the status read-only in persisted Planner input preserves old sessions, while clearing
        // it here ensures current-v5 output can never acquire a second owner for the same fact.
        update.selfCriticismStatus = nil

        // Exploration owns the one self-critical proposition. Once its relationship and first
        // Tender frame have been committed, later responsibility, boundary, support, repair,
        // protection, or change language belongs to episode/Fierce evidence and cannot replace
        // that endpoint. For sessions polluted by older builds, mechanically restore the endpoint
        // already present in the committed relation on the next successful turn.
        let reflectionAnchorIsCommitted = session.protocolStage == .directReflection
            && session.semanticMemory.reflectionPhase != .exploratory
            && session.semanticMemory.reflectionFrame != nil
        if reflectionAnchorIsCommitted {
            let canonicalStatement = CurrentV5SelfCriticismLineage.canonicalStatement(
                in: session.semanticMemory
            )
            update.selfCriticalStatement = canonicalStatement
                == session.semanticMemory.selfCriticalStatement
                ? nil
                : canonicalStatement
        }
        // Event Disclosure establishes the canonical episode, but it does not permanently own
        // facts about that episode. During direct Reflection the person may naturally add a
        // concrete behavior, process, condition, consequence, or controllable part that later
        // Tender/Fierce work must be able to read directly. Keep those sparse user-grounded facts
        // in the same episode aggregate instead of locking them inside selfCriticismLink. Card,
        // practice, narrative, and system-authored material still have no write path here.
        let episodeEvidenceOperations: Set<PlannerSemanticOperation> = [
            .clarifyEvent,
            .advanceToCardConsent,
            .continueExploratoryReflection,
            .continueTenderReflection,
            .continueTenderGroundedFierceReflection,
            .synthesizeDirectReflection,
        ]
        if !episodeEvidenceOperations.contains(operation) {
            update.episodeStructure = nil
        }

        // Swift does not decide whether language is self-critical. Once the Planner supplies the
        // exact nonempty statement, Swift derives the persisted presence summary mechanically.
        if !reflectionAnchorIsCommitted,
           let statement = update.selfCriticalStatement {
            let clean = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                update.selfCriticalStatement = nil
            } else {
                update.selfCriticalStatement = clean
                update.selfCriticismStatus = .present
            }
        }

        // A malformed relation is redundant protocol structure, not new semantic evidence. Drop
        // it before persistence unless its endpoint is the exact candidate statement. The user
        // statement remains durable, and a later Planner turn can supply the aligned relation;
        // Swift never substitutes Card or episode wording for it.
        if update.selfCriticismLink != nil {
            let candidateStatement = update.selfCriticalStatement
                ?? session.semanticMemory.selfCriticalStatement
            if candidateStatement?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                // Current Exploration cannot create an unscoped relation. Later phases retain
                // compatibility with already-entered pre-v85 sessions that never persisted the
                // separate statement field.
                if operation == .continueExploratoryReflection {
                    update.selfCriticismLink = nil
                }
            } else if CurrentV5SelfCriticismLineage.alignedLink(
                in: session.semanticMemory,
                applying: update
            ) == nil {
                update.selfCriticismLink = nil
            }
        }

        // Event presence is protocol metadata. The model supplies only grounded arrays; Swift
        // derives their internal presence state in the one candidate-state compiler.
        if let episode = update.episodeStructure {
            update.episodeStructure = episode.normalizingGroundedPresence()
        }

        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }

        func committedImageAnchor() -> String? {
            let development = session.semanticMemory.cardDevelopmentEvidence
            let components = [
                clean(development?.relationOrAction),
                clean(development?.anticipatedChangeOrChoice),
            ].compactMap { $0 }
            if !components.isEmpty { return components.joined(separator: "；") }
            if let focus = clean(development?.projectiveFocus) { return focus }

            // Development is optional semantic enrichment. Reality Connection must still be able
            // to preserve a user's grounded reality-side relation after the one Development act
            // has completed. Observation is mandatory, user-authored Card context, so it provides
            // the deterministic image anchor without Swift inventing an interpretation or asking
            // the person/Planner to restate the Card.
            let observations = session.semanticMemory.cardObservationEvidence?
                .userDescribedElements
                .compactMap(clean) ?? []
            return observations.isEmpty ? nil : observations.joined(separator: "；")
        }

        // Accept both the v72 semantic surface and the old tagged object as decode-only input.
        // The current user turn plus operation/state determine provenance and status locally.
        let legacyConnection = patch.cardConnectionTurnOutcome?.connection?.normalizedConfirmed
        let suppliedImageRelation = clean(patch.cardConnectionEvidence?.imageRelation)
            ?? clean(legacyConnection?.imageRelation)
        let suppliedRealityMapping = clean(patch.cardConnectionEvidence?.realityMapping)
            ?? clean(legacyConnection?.realityMapping)
        let connectionOperation = [
            PlannerSemanticOperation.continueOpenCardConnection,
            .offerCardConnectionScaffold,
            .establishUserAuthoredCardConnection,
            .reviseCardConnectionCandidate,
        ].contains(operation)
        if connectionOperation, let suppliedRealityMapping {
            let imageRelation = suppliedImageRelation
                ?? (operation == .reviseCardConnectionCandidate
                    ? clean(session.semanticMemory.pendingCardRealityConnection?.imageRelation)
                    : committedImageAnchor())
            if let imageRelation {
                update.cardRealityConnection = TurnCardRealityConnection(
                    imageRelation: imageRelation,
                    realityMapping: suppliedRealityMapping,
                    source: operation == .reviseCardConnectionCandidate
                        ? .userRevised
                        : .userAuthored
                )
                update.cardConnectionOutcome = .connectionConfirmed
                if operation != .reviseCardConnectionCandidate {
                    update.clearPendingCardRealityConnection = true
                }
            }
        }

        if let contribution = patch.reflectionContribution,
           update.reflectionFrame == nil {
            let evidence = contribution.evidenceBasis.compactMap { value -> TurnReflectionEvidence? in
                guard let content = clean(value) else { return nil }
                return .init(source: .latestUserAnswer, content: content)
            }
            let delta = clean(contribution.reflectionDelta)
            switch operation {
            case .continueExploratoryReflection:
                if let delta {
                    // Exploration completion may carry the minimum LLM-authored Tender handoff.
                    // Swift still owns phase, frame action, and provenance; this prevents a second
                    // Planner turn from having to rediscover the first bounded understanding.
                    update.reflectionFrame = TurnReflectionFrame(
                        mode: .tender,
                        action: .softenGlobalSelfJudgment,
                        evidenceBasis: evidence,
                        dimensions: contribution.dimensions,
                        reflectionDelta: delta,
                        fierceEvidence: nil
                    )
                }
            case .continueTenderReflection:
                if let delta {
                    update.reflectionFrame = TurnReflectionFrame(
                        mode: .tender,
                        action: .softenGlobalSelfJudgment,
                        evidenceBasis: evidence,
                        dimensions: contribution.dimensions.isEmpty
                            ? session.semanticMemory.reflectionFrame?.dimensions ?? []
                            : contribution.dimensions,
                        reflectionDelta: delta,
                        fierceEvidence: nil
                    )
                }
            case .continueTenderGroundedFierceReflection:
                if session.semanticMemory.reflectionPhase == .tender,
                   contribution.fierceEvidence == nil,
                   let delta {
                    // A user revision and the decision to inspect one reality candidate can be
                    // one semantic turn. Preserve that revised bounded understanding while Swift
                    // opens Fierce; do not require another confirmation round.
                    update.reflectionFrame = TurnReflectionFrame(
                        mode: .tender,
                        action: .softenGlobalSelfJudgment,
                        evidenceBasis: evidence,
                        dimensions: contribution.dimensions.isEmpty
                            ? session.semanticMemory.reflectionFrame?.dimensions ?? []
                            : contribution.dimensions,
                        reflectionDelta: delta,
                        fierceEvidence: nil
                    )
                } else if let fierce = contribution.fierceEvidence,
                   let direction = fierce.direction,
                   let delta {
                    let action: TurnReflectionAction = switch direction {
                    case .repair: .identifyRepairDirection
                    case .protect: .identifyProtectionDirection
                    case .change: .identifyChangeDirection
                    }
                    update.reflectionFrame = TurnReflectionFrame(
                        mode: .fierce,
                        action: action,
                        evidenceBasis: evidence,
                        dimensions: contribution.dimensions,
                        reflectionDelta: delta,
                        fierceEvidence: TurnFierceEvidence(
                            behavior: clean(fierce.behavior) ?? "",
                            impact: clean(fierce.impact) ?? "",
                            direction: direction
                        )
                    )
                }
            case .synthesizeDirectReflection:
                if let delta {
                    update.reflectionFrame = TurnReflectionFrame(
                        mode: .tender,
                        action: .synthesizeUnderstanding,
                        evidenceBasis: evidence,
                        dimensions: contribution.dimensions,
                        reflectionDelta: delta,
                        fierceEvidence: nil
                    )
                }
            default:
                break
            }
        }
        if operation == .continueExploratoryReflection {
            let hasAtomicTenderHandoff = clean(
                patch.reflectionContribution?.reflectionDelta
            ) != nil && CurrentV5SelfCriticismLineage.alignedLink(
                in: session.semanticMemory,
                applying: update
            ) != nil
            if !hasAtomicTenderHandoff {
                // A raw/misplaced Tender frame cannot become part of an incomplete Exploration
                // act. Only the compiled phase-outcome handoff with an aligned link survives.
                update.reflectionFrame = nil
            }
        }

        if let contribution = patch.practiceContribution {
            let compiledKind: TurnPracticeKind = {
                if let legacyKind = contribution.proposal?.kind { return legacyKind }
                switch session.semanticMemory.reflectionFrame?.fierceEvidence?.direction {
                case .repair: return .repair
                case .protect: return .protect
                case .change: return .change
                case nil: return .care
                }
            }()
            let proposal = contribution.proposal.map {
                TurnPracticeProposal(
                    id: "",
                    kind: compiledKind,
                    content: $0.content,
                    basis: $0.basis,
                    status: .pendingConfirmation,
                    source: .assistantProposed
                )
            }
            update.practiceTransition = TurnPracticeTransition(
                transactionID: "",
                narrativeReferenceID: nil,
                proposal: proposal,
                noActionReason: contribution.noActionReason
            )
        }

        // Canonicalize every practice payload—new semantic draft or legacy full object—at the
        // single Swift compiler boundary. The Projector only validates and moves workflow state.
        if operation == .proposePractice,
           let proposal = update.practiceTransition?.proposal {
            let identifier = UUID().uuidString
            update.practiceTransition = TurnPracticeTransition(
                transactionID: identifier,
                narrativeReferenceID: nil,
                proposal: TurnPracticeProposal(
                    id: identifier,
                    kind: proposal.kind,
                    content: proposal.content,
                    basis: proposal.basis,
                    status: .pendingConfirmation,
                    source: .assistantProposed
                ),
                noActionReason: nil
            )
        } else if operation == .resolvePractice,
                  let active = session.semanticMemory.practiceTransition,
                  let activeProposal = active.proposal {
            // `resolvePractice` already says that this turn resolves the one active proposal.
            // A sparse Planner patch therefore has one deterministic meaning: accept it. Only a
            // supplied decline reason or revised proposal changes that default. Requiring the LLM
            // to restate the pending transaction made ordinary natural acceptance fail
            // structurally; no particular user phrase is inspected here.
            let supplied = update.practiceTransition
            if let reason = supplied?.noActionReason {
                update.practiceTransition = TurnPracticeTransition(
                    transactionID: active.transactionID,
                    narrativeReferenceID: active.narrativeReferenceID,
                    proposal: activeProposal,
                    noActionReason: reason
                )
            } else if let proposal = supplied?.proposal {
                let revised = proposal.kind != activeProposal.kind
                    || proposal.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != activeProposal.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    || proposal.basis.trimmingCharacters(in: .whitespacesAndNewlines)
                        != activeProposal.basis.trimmingCharacters(in: .whitespacesAndNewlines)
                update.practiceTransition = TurnPracticeTransition(
                    transactionID: active.transactionID,
                    narrativeReferenceID: active.narrativeReferenceID,
                    proposal: TurnPracticeProposal(
                        id: activeProposal.id,
                        kind: revised ? proposal.kind : activeProposal.kind,
                        content: revised ? proposal.content : activeProposal.content,
                        basis: revised ? proposal.basis : activeProposal.basis,
                        status: .confirmed,
                        source: revised ? .userRevised : .assistantProposed
                    ),
                    noActionReason: nil
                )
            } else {
                update.practiceTransition = TurnPracticeTransition(
                    transactionID: active.transactionID,
                    narrativeReferenceID: active.narrativeReferenceID,
                    proposal: TurnPracticeProposal(
                        id: activeProposal.id,
                        kind: activeProposal.kind,
                        content: activeProposal.content,
                        basis: activeProposal.basis,
                        status: .confirmed,
                        source: .assistantProposed
                    ),
                    noActionReason: nil
                )
            }
        }

        // The first visible-image answer is the one Card turn where an empty sparse patch is not
        // harmless: without typed observation evidence the committed state remains `.none` and
        // every later Development/Reality operation is forced back to Observation. Require only
        // structural presence here; the Planner remains the sole judge of what the image answer
        // means and Swift never reads the raw dialogue.
        let isAnsweringInitialCardObservation =
            session.protocolStage == .cardReflection
            && session.semanticMemory.nextPrompt?.purpose == "cardObservation"
        let hasCommittedCardObservation =
            session.semanticMemory.cardObservationEvidence?.hasContent == true
        let patchContainsCardObservation =
            update.cardObservationEvidence?.hasContent == true
        if isAnsweringInitialCardObservation,
           !hasCommittedCardObservation,
           !patchContainsCardObservation {
            throw CurrentV5CoreError.payloadInvalid(
                failure: .cardObservationEvidenceMissing
            )
        }

        guard !update.legacyConnectionFieldsPresentInPayload else {
            throw CurrentV5CoreError.payloadInvalid(
                failure: .legacyCardConnectionFieldsPresent
            )
        }

        let availableProfiles = LLMTurnContextualTrackingProfile.currentV5Profiles(in: session)
        if availableProfiles.isEmpty {
            // There is nothing to classify. A non-nil decision would necessarily refer to input
            // Swift did not supply and therefore cannot be normalized safely.
            guard patch.contextualTrackingDecision == nil else {
                throw CurrentV5CoreError.payloadInvalid(
                    failure: .contextualTrackingDecisionInvalid
                )
            }
        } else {
            // Preserve the review's three semantic states. Omission means the Planner has not
            // reviewed Tracking on this turn; all metrics rejected means reviewed/not used; one
            // preferred qualifying metric means reviewed/selected. Never compile nil into no-use.
            let decision = patch.contextualTrackingDecision
            if let decision {
                let suppliedReferences = availableProfiles.flatMap { profile in
                    profile.metrics.map {
                        ContextualTrackingMetricIdentity(
                            profileID: profile.profileID,
                            metric: $0.metric
                        )
                    }
                }
                let expectedReferences = Set(suppliedReferences)
                let classifiedReferences = decision.metricEligibility.map(\.reference)
                let classifiedReferenceSet = Set(classifiedReferences)
                let qualifying = decision.metricEligibility.filter { $0.status == .qualifies }
                let preferredQualifying = qualifying.filter(\.preferred)

                guard suppliedReferences.count == expectedReferences.count,
                      classifiedReferences.count == classifiedReferenceSet.count,
                      classifiedReferenceSet == expectedReferences,
                      (
                        qualifying.count <= 1
                            || preferredQualifying.count == 1
                      ) else {
                    throw CurrentV5CoreError.payloadInvalid(
                        failure: .contextualTrackingDecisionInvalid
                    )
                }
                if qualifying.isEmpty {
                    // A complete all-doesNotQualify classification is the Planner's completed
                    // reviewed/not-used decision; omission never reaches this branch.
                    update.contextCueOffered = false
                } else {
                    guard session.protocolStage == .directReflection,
                          [TurnReflectionPhase.exploratory, .tender]
                            .contains(session.semanticMemory.reflectionPhase),
                          [.continueExploratoryReflection, .continueTenderReflection]
                            .contains(operation) else {
                        throw CurrentV5CoreError.payloadInvalid(
                            failure: .contextualTrackingDecisionInvalid
                        )
                    }
                    update.contextCueOffered = true
                }
            }
        }
        if let relationship = update.contextRelationship {
            guard [
                .continueExploratoryReflection,
                .continueTenderReflection,
                .synthesizeDirectReflection,
            ].contains(operation),
                  session.protocolStage == .directReflection,
                  [.exploratory, .tender].contains(session.semanticMemory.reflectionPhase),
                  session.contextualLoadInference?.relevance == .offered else {
                throw CurrentV5CoreError.payloadInvalid(failure: .malformedSemanticPayload)
            }
            if [.related, .partlyRelated].contains(relationship.relevance) {
                guard relationship.userInterpretation?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw CurrentV5CoreError.payloadInvalid(failure: .malformedSemanticPayload)
                }
            }
        }

        switch operation {
        case .continueOpenCardConnection, .offerCardConnectionScaffold:
            if update.cardRealityConnection?.normalizedConfirmed == nil {
                update.cardConnectionOutcome = .noConnectionFound
            }
        case .establishUserAuthoredCardConnection, .reviseCardConnectionCandidate:
            guard update.cardRealityConnection?.normalizedConfirmed != nil else {
                throw CurrentV5CoreError.payloadInvalid(failure: .cardConnectionIncomplete)
            }
        case .acceptCardConnectionCandidate, .rejectCardConnectionCandidate:
            break
        default:
            // Connection evidence supplied outside the Card connection task has no authority and
            // cannot mutate state. It remains harmless transport residue rather than a hard stop.
            update.cardRealityConnection = nil
        }

        switch operation {
        case .establishUserAuthoredCardConnection,
             .acceptCardConnectionCandidate,
             .reviseCardConnectionCandidate,
             .bypassCardConnectionToDirectReflection,
             .authorizeCardGuidance:
            // Card connection operations establish material; they never smuggle in a Reflection
            // frame before the explicit Exploration completion boundary.
            update.reflectionFrame = nil
        default:
            break
        }

        if operation == .provideSafetySupport {
            return TurnSemanticMemoryUpdate()
        }
        return update
    }
}

/// The one current-v5 protocol projector. It does not read raw dialogue and has no fallback or
/// legacy tuple input. Every legal semantic operation maps to exactly one Swift-owned state
/// transition and one Writer directive.
private struct CurrentV5CanonicalProjector {
    func project(
        operation: PlannerSemanticOperation,
        memoryUpdate: TurnSemanticMemoryUpdate,
        responseFocus: String,
        hasReflectionContribution: Bool,
        reflectionProgressionMeaning: CurrentV5ReflectionProgressionMeaning?,
        inspectedRealityCandidateReference: String?,
        session: ReflectionSession
    ) throws -> ProjectedExecutableTurnPlan {
        let sourceStage = session.protocolStage
        let focus = responseFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let preTurnEventState = EffectiveEventDisclosureState(
            memory: session.semanticMemory
        )
        let eventState = EffectiveEventDisclosureState(
            memory: session.semanticMemory,
            update: memoryUpdate
        )
        var cardCandidate = session
        cardCandidate.semanticMemory.apply(memoryUpdate)
        let cardState = EffectiveCardSemanticState(session: cardCandidate)

        func decision(_ update: TurnSemanticMemoryUpdate) -> PlannerSemanticDecision {
            PlannerSemanticDecision(
                operation: operation,
                memoryUpdate: update,
                responseFocus: focus.isEmpty ? nil : focus,
                clarificationFocus: focus.isEmpty ? nil : focus
            )
        }
        func make(
            stage: ReflectionProtocolStage,
            intent: TurnReplyIntent,
            update: TurnSemanticMemoryUpdate = memoryUpdate,
            action: TurnLocalActionRequest = .none,
            next: TurnNextPrompt = .none,
            resolved: TurnResolvedConfirmation? = nil
        ) -> ProjectedExecutableTurnPlan {
            ProjectedExecutableTurnPlan(
                semanticDecision: decision(update),
                sourceStage: sourceStage,
                requestedStage: stage,
                replyIntent: intent,
                localAction: action,
                nextPrompt: next,
                resolvedConfirmation: resolved,
                memoryUpdate: update,
                responseFocus: focus.isEmpty ? nil : focus
            )
        }
        func question(
            _ purpose: String,
            _ structuralFocus: String,
            referenceID: String? = nil
        ) -> TurnNextPrompt {
            // responseFocus remains an ephemeral instruction in CurrentV5WriterDirective. The
            // persisted nextPrompt records interaction identity only, never the Planner's draft
            // interpretation or proposed wording for a later turn. Fierce reuses referenceID only
            // for the exact Swift-projected reality candidate already selected at the Tender
            // boundary; it never stores the Planner's semantic classification or wording.
            let prompt = TurnNextPrompt.openQuestion(
                purpose: purpose,
                focus: structuralFocus
            )
            if let referenceID {
                return prompt.assigningReferenceID(referenceID)
            }
            return prompt
        }
        let selfCriticismAttributionFocus =
            "clarify_self_criticism_attribution_relation"
        func confirmation(
            _ target: TurnConfirmationTarget,
            referenceID: String? = nil
        ) -> TurnNextPrompt {
            .confirmationRequest(target: target, referenceID: referenceID)
        }
        func requireStage(_ stages: ReflectionProtocolStage...) throws {
            guard stages.contains(sourceStage) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .sourceStageMismatch
                )
            }
        }
        func settingReflectionPhase(
            _ phase: TurnReflectionPhase,
            in source: TurnSemanticMemoryUpdate = memoryUpdate
        ) -> TurnSemanticMemoryUpdate {
            var update = source
            update.reflectionPhase = phase
            return update
        }
        func candidateHasGroundedSelfCriticismLink(
            _ update: TurnSemanticMemoryUpdate
        ) -> Bool {
            var candidate = session.semanticMemory
            candidate.apply(update)
            guard let link = CurrentV5SelfCriticismLineage.alignedLink(
                in: candidate
            ) else {
                return false
            }
            return !candidate.invalidatedInterpretations.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == link
            }
        }
        func doesNotReuseInvalidatedInterpretation(
            _ frame: TurnReflectionFrame,
            update: TurnSemanticMemoryUpdate
        ) -> Bool {
            let invalidated = Set(
                (session.semanticMemory.invalidatedInterpretations
                 + (update.invalidatedInterpretations ?? []))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            guard !invalidated.isEmpty else { return true }
            let asserted = Set(
                (frame.evidenceBasis.map(\.content) + [frame.reflectionDelta])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            // These are exact typed propositions selected by the Planner, not a language keyword
            // detector. Semantic paraphrase avoidance remains the Planner's responsibility.
            return invalidated.isDisjoint(with: asserted)
        }
        func carriesCanonicalCardConnection(_ frame: TurnReflectionFrame) -> Bool {
            guard let connection = session.semanticMemory.cardRealityConnection?.normalizedConfirmed
            else { return true }
            let canonical = Set([
                connection.imageRelation.trimmingCharacters(in: .whitespacesAndNewlines),
                connection.realityMapping.trimmingCharacters(in: .whitespacesAndNewlines),
            ].filter { !$0.isEmpty })
            return frame.evidenceBasis.contains { evidence in
                evidence.source == .cardRealityConnection
                    && canonical.contains(
                        evidence.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
            }
        }
        func usesOnlyConfirmedContext(
            _ frame: TurnReflectionFrame,
            update: TurnSemanticMemoryUpdate
        ) -> Bool {
            let contextEvidence = frame.evidenceBasis.filter { $0.source == .confirmedContext }
            guard !contextEvidence.isEmpty else { return true }
            let relationship = update.contextRelationship
                ?? session.semanticMemory.contextRelationship
            guard let relationship,
                  [.related, .partlyRelated].contains(relationship.relevance),
                  let interpretation = relationship.userInterpretation?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !interpretation.isEmpty else { return false }
            return contextEvidence.allSatisfy {
                $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == interpretation
            }
        }
        func continuesCommittedReflectionEvidence(_ frame: TurnReflectionFrame) -> Bool {
            guard let committed = session.semanticMemory.reflectionFrame else { return true }
            let priorReality = Set(committed.evidenceBasis.filter {
                $0.source != .cardRealityConnection
            }.map {
                "\($0.source.rawValue)\u{1F}\($0.content.trimmingCharacters(in: .whitespacesAndNewlines))"
            })
            guard !priorReality.isEmpty else { return false }
            return frame.evidenceBasis.contains {
                $0.source != .cardRealityConnection && priorReality.contains(
                    "\($0.source.rawValue)\u{1F}\($0.content.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }
        func canonicalSynthesisFrame(
            from proposed: TurnReflectionFrame
        ) -> TurnReflectionFrame? {
            guard let committed = session.semanticMemory.reflectionFrame else { return nil }

            // Synthesis does not ask the model to serialize provenance Swift already owns. Start
            // from the last committed Tender/Fierce frame, restore the canonical Card connection
            // when needed, and accept only latest-answer evidence during an in-place revision.
            var inherited = committed.evidenceBasis.filter {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let connection = session.semanticMemory.cardRealityConnection?.normalizedConfirmed,
               !inherited.contains(where: { evidence in
                   evidence.source == .cardRealityConnection
                       && [connection.imageRelation, connection.realityMapping].contains(
                           evidence.content.trimmingCharacters(in: .whitespacesAndNewlines)
                       )
               }) {
                inherited.append(
                    .init(source: .cardRealityConnection, content: connection.realityMapping)
                )
            }
            if session.semanticMemory.reflectionPhase == .synthesis {
                inherited.append(contentsOf: proposed.evidenceBasis.filter {
                    [.latestUserAnswer, .confirmedContext].contains($0.source)
                        && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
            }
            var seen = Set<String>()
            inherited = inherited.filter { evidence in
                seen.insert(
                    "\(evidence.source.rawValue)\u{1F}"
                        + evidence.content.trimmingCharacters(in: .whitespacesAndNewlines)
                ).inserted
            }

            let fierceEvidence: TurnFierceEvidence?
            switch session.semanticMemory.reflectionPhase {
            case .fierce:
                fierceEvidence = committed.fierceEvidence
            case .synthesis where proposed.mode == .fierce:
                fierceEvidence = committed.fierceEvidence
            case .exploratory, .tender, .synthesis:
                fierceEvidence = nil
            }
            return TurnReflectionFrame(
                mode: proposed.mode,
                action: proposed.action,
                evidenceBasis: inherited,
                dimensions: proposed.dimensions.isEmpty
                    ? committed.dimensions
                    : proposed.dimensions,
                reflectionDelta: proposed.reflectionDelta,
                fierceEvidence: fierceEvidence
            )
        }
        func canonicalTenderFrame(
            from proposed: TurnReflectionFrame,
            update: TurnSemanticMemoryUpdate
        ) -> TurnReflectionFrame {
            // The Planner owns the compassionate understanding (`action` + `reflectionDelta`).
            // Swift owns already-committed provenance. Preserve that provenance here instead of
            // requiring the model to serialize exact copies of it again at the Tender boundary.
            // This never creates a frame, chooses an action, or writes a reflection delta.
            var evidence = session.semanticMemory.reflectionFrame?.evidenceBasis ?? []
            evidence.append(contentsOf: proposed.evidenceBasis.filter {
                $0.source != .cardRealityConnection
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

            let invalidated = Set(
                (session.semanticMemory.invalidatedInterpretations
                 + (update.invalidatedInterpretations ?? []))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            let relationship = CurrentV5SelfCriticismLineage.committedCompatibleLink(
                in: session.semanticMemory,
                applying: update
            )
            if let staleRelationship = session.semanticMemory.selfCriticismLink,
               staleRelationship != relationship {
                evidence.removeAll {
                    $0.source == .episode
                        && $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            == staleRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if let relationship {
                if !relationship.isEmpty,
                   !invalidated.contains(relationship),
                   !evidence.contains(where: {
                       $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == relationship
                   }) {
                // `selfCriticismLink` is already committed lived-reality evidence. Copying it into
                // provenance does not ask Swift to infer why the judgment exists.
                    evidence.append(.init(source: .episode, content: relationship))
                }
            }
            if let connection = session.semanticMemory.cardRealityConnection?.normalizedConfirmed {
                evidence.removeAll { $0.source == .cardRealityConnection }
                evidence.append(
                    .init(source: .cardRealityConnection, content: connection.realityMapping)
                )
            }

            var seen = Set<String>()
            evidence = evidence.filter { item in
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return false }
                return seen.insert("\(item.source.rawValue)\u{1F}\(content)").inserted
            }
            return TurnReflectionFrame(
                mode: proposed.mode,
                action: proposed.action,
                evidenceBasis: evidence,
                dimensions: proposed.dimensions,
                reflectionDelta: proposed.reflectionDelta,
                fierceEvidence: proposed.fierceEvidence
            )
        }
        func canonicalFierceFrame(
            from proposed: TurnReflectionFrame
        ) -> TurnReflectionFrame? {
            guard let committed = session.semanticMemory.reflectionFrame else { return nil }

            // Fierce adds one current-turn semantic contribution to the reflection that Swift has
            // already committed. The model must not reproduce episode, Card, or confirmed-context
            // provenance merely because the phase changed. Preserve that lineage here, then add
            // only the new evidence carried by this Fierce contribution.
            var evidence = committed.evidenceBasis.filter {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            evidence.append(contentsOf: proposed.evidenceBasis.filter {
                $0.source != .cardRealityConnection
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

            // Card provenance is derived only from the confirmed canonical connection. A Planner
            // contribution cannot create or replace it, and an old sparse frame need not repeat it.
            if let connection = session.semanticMemory.cardRealityConnection?.normalizedConfirmed {
                evidence.removeAll { $0.source == .cardRealityConnection }
                evidence.append(
                    .init(source: .cardRealityConnection, content: connection.realityMapping)
                )
            }

            var seen = Set<String>()
            evidence = evidence.filter { item in
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return false }
                return seen.insert("\(item.source.rawValue)\u{1F}\(content)").inserted
            }
            return TurnReflectionFrame(
                mode: .fierce,
                action: proposed.action,
                evidenceBasis: evidence,
                dimensions: proposed.dimensions.isEmpty
                    ? committed.dimensions
                    : proposed.dimensions,
                reflectionDelta: proposed.reflectionDelta,
                fierceEvidence: proposed.fierceEvidence
            )
        }
        func protocolShapedTenderFrame(
            from update: TurnSemanticMemoryUpdate
        ) throws -> TurnReflectionFrame {
            guard let supplied = update.reflectionFrame else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .tenderFrameMissing
                )
            }
            guard supplied.fierceEvidence == nil else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .unexpectedFierceEvidence
                )
            }
            let delta = supplied.reflectionDelta
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !delta.isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .tenderDeltaMissing
                )
            }

            // `continueTenderReflection` is the Planner's semantic decision. Tender mode, its
            // non-Fierce protocol action, provenance, and empty Fierce slot are the one Swift-owned
            // representation of that decision. `reflectionDelta` remains exactly the model's
            // proposed understanding. `responseFocus` is Writer-only and never persistent state.
            let shaped = TurnReflectionFrame(
                mode: .tender,
                action: supplied.action.currentV5ProvidesTenderDistinction
                    ? supplied.action
                    : .softenGlobalSelfJudgment,
                evidenceBasis: supplied.evidenceBasis,
                dimensions: supplied.dimensions,
                reflectionDelta: delta,
                fierceEvidence: nil
            )
            let canonical = canonicalTenderFrame(from: shaped, update: update)
            let repairsStaleLineage: Bool = {
                guard let stored = session.semanticMemory.selfCriticismLink,
                      CurrentV5SelfCriticismLineage.alignedLink(
                          in: session.semanticMemory
                      ) == nil,
                      let replacement = CurrentV5SelfCriticismLineage.alignedLink(
                          in: session.semanticMemory,
                          applying: update
                      ) else { return false }
                return replacement != stored
            }()
            guard canonical.hasNonemptyEvidence,
                  canonical.hasRealityEvidence,
                  carriesCanonicalCardConnection(canonical),
                  usesOnlyConfirmedContext(canonical, update: update),
                  continuesCommittedReflectionEvidence(canonical) || repairsStaleLineage else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .tenderEvidenceMissing
                )
            }
            guard doesNotReuseInvalidatedInterpretation(canonical, update: update) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .rejectedInterpretationReused
                )
            }
            let candidateStatement = update.selfCriticalStatement
                ?? session.semanticMemory.selfCriticalStatement
            if candidateStatement?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || session.semanticMemory.cardRealityConnection?.normalizedConfirmed != nil {
                guard CurrentV5SelfCriticismLineage.committedCompatibleLink(
                    in: session.semanticMemory,
                    applying: update
                ) != nil else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .tenderEvidenceMissing
                    )
                }
            }
            return canonical
        }
        func protocolShapedFierceFrame(
            from update: TurnSemanticMemoryUpdate
        ) throws -> TurnReflectionFrame {
            guard let supplied = update.reflectionFrame,
                  let fierceEvidence = supplied.fierceEvidence,
                  supplied.hasReflectionDelta else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .fierceFrameIncomplete
                )
            }

            // The operation and typed direction have one protocol representation. This shaping is
            // structural only; Swift does not decide whether the proposed direction is meaningful.
            let action: TurnReflectionAction = switch fierceEvidence.direction {
            case .repair: .identifyRepairDirection
            case .protect: .identifyProtectionDirection
            case .change: .identifyChangeDirection
            }
            let shaped = TurnReflectionFrame(
                mode: .fierce,
                action: action,
                evidenceBasis: supplied.evidenceBasis,
                dimensions: supplied.dimensions,
                reflectionDelta: supplied.reflectionDelta,
                fierceEvidence: fierceEvidence
            )
            guard let canonical = canonicalFierceFrame(from: shaped),
                  canonical.hasCurrentV5GroundedFierceContribution,
                  carriesCanonicalCardConnection(canonical),
                  usesOnlyConfirmedContext(canonical, update: update),
                  continuesCommittedReflectionEvidence(canonical) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .fierceFrameIncomplete
                )
            }
            return canonical
        }
        func protocolShapedSynthesisFrame(
            from update: TurnSemanticMemoryUpdate
        ) throws -> TurnReflectionFrame {
            guard let committed = session.semanticMemory.reflectionFrame else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisEvidenceInvalid
                )
            }
            guard let supplied = update.reflectionFrame else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisFrameMissing
                )
            }
            let delta = supplied.reflectionDelta
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !delta.isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisDeltaMissing
                )
            }
            let normalizedDelta = delta
                .precomposedStringWithCompatibilityMapping
                .lowercased()
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            let normalizedCommittedDelta = committed.reflectionDelta
                .precomposedStringWithCompatibilityMapping
                .lowercased()
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            guard !normalizedDelta.isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisDeltaMissing
                )
            }
            if normalizedDelta == normalizedCommittedDelta {
                // Synthesis may preserve the already accepted meaning, but it is still a distinct
                // semantic act and cannot be an exact replay of the committed Tender/Fierce text.
                // In-place Synthesis revision follows the same rule.
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisDeltaMissing
                )
            }

            let carriesFierce = [TurnReflectionPhase.fierce, .synthesis].contains(
                session.semanticMemory.reflectionPhase
            ) && committed.hasCurrentV5GroundedFierceContribution
            let shaped = TurnReflectionFrame(
                mode: carriesFierce ? .fierce : .tender,
                action: .synthesizeUnderstanding,
                evidenceBasis: supplied.evidenceBasis,
                dimensions: supplied.dimensions.isEmpty
                    ? committed.dimensions
                    : supplied.dimensions,
                reflectionDelta: delta,
                fierceEvidence: carriesFierce ? committed.fierceEvidence : nil
            )
            guard let canonical = canonicalSynthesisFrame(from: shaped),
                  canonical.hasNonemptyEvidence,
                  canonical.hasRealityEvidence,
                  carriesCanonicalCardConnection(canonical),
                  usesOnlyConfirmedContext(canonical, update: update),
                  continuesCommittedReflectionEvidence(canonical),
                  doesNotReuseInvalidatedInterpretation(canonical, update: update) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .synthesisEvidenceInvalid
                )
            }
            return canonical
        }
        switch operation {
        case .clarifyEvent:
            try requireStage(.contextualDisclosure)
            guard !isEventDisclosureCoreComplete(preTurnEventState) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .eventAlreadyComplete
                )
            }
            if isEventDisclosureCoreComplete(eventState) {
                // The Planner completed the current Event act. The operation remains Event;
                // only the post-turn workflow enters Card Consent.
                return make(
                    stage: .cardConsent,
                    intent: .inviteCardConsent,
                    next: confirmation(.cardConsent)
                )
            }
            guard !focus.isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .responseFocusMissing
                )
            }
            let purpose: TurnDisclosureQuestionPurpose
            if !eventState.hasConcreteFocalEvent { purpose = .identifyConcreteEpisode }
            else if !eventState.hasEventProcess { purpose = .clarifyEventProcess }
            else if !eventState.hasUserBehaviorOrOmission { purpose = .clarifyBehavior }
            else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .eventAlreadyComplete
                )
            }
            return make(
                stage: .contextualDisclosure,
                intent: .exploreContext,
                next: .openQuestion(
                    purpose: purpose.rawValue,
                    focus: purpose.rawValue,
                    disclosurePurpose: purpose,
                    disclosureTarget: purpose.target
                )
            )

        case .advanceToCardConsent:
            try requireStage(.contextualDisclosure)
            guard isEventDisclosureCoreComplete(preTurnEventState) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .eventCoreIncomplete
                )
            }
            return make(
                stage: .cardConsent,
                intent: .inviteCardConsent,
                next: confirmation(.cardConsent)
            )

        case .inviteCardConsent:
            try requireStage(.cardConsent)
            return make(
                stage: .cardConsent,
                intent: .inviteCardConsent,
                next: confirmation(.cardConsent)
            )

        case .acknowledgeCardConsent:
            try requireStage(.cardConsent)
            return make(
                stage: .cardConsent,
                intent: .acknowledgeCardConsent,
                action: .init(kind: .drawRandomCard),
                resolved: .init(
                    target: .cardConsent,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .declineCardConsent:
            try requireStage(.cardConsent)
            return make(
                stage: .directReflection,
                intent: .acknowledgeCardDecline,
                update: settingReflectionPhase(.exploratory),
                resolved: .init(
                    target: .cardConsent,
                    decision: .declined,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .continueCardObservation:
            try requireStage(.cardReflection)
            guard session.cardDisplayState == .displayed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardNotDisplayed
                )
            }
            guard cardState.canonicalConnectionExists == false else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionAlreadyExists
                )
            }
            guard cardState.observationEvidenceExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardObservationMissing
                )
            }
            // Observation completes only the current visible-image act. Even if the Planner also
            // captured relationship material from a rich answer, the post-turn interaction first
            // enters Development; this turn is never relabeled or skipped into Reality Connection.
            return make(
                stage: .cardReflection,
                intent: .developCardImage,
                next: question("cardDevelopment", "anticipated_change")
            )

        case .continueCardDevelopment:
            try requireStage(.cardReflection)
            guard cardState.observationEvidenceExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardObservationMissing
                )
            }
            // Development is one visible conversational act, not a typed-evidence completion
            // gate. The person's answer remains available in the transcript even when the
            // Planner does not produce an optional aggregate. Repeating Development until that
            // aggregate is populated would make transport completeness control the dialogue.
            // Keep the current act as Development and deterministically start Reality Connection
            // on the next turn; never fabricate image meaning locally.
            return make(
                stage: .cardReflection,
                intent: .inviteCardConnection,
                next: question("cardRealityConnection", "connect_image_to_reality")
            )

        case .inviteRealityConnection:
            try requireStage(.cardReflection)
            guard cardState.observationEvidenceExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardObservationMissing
                )
            }
            guard !cardState.pendingCandidateExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateAlreadyPending
                )
            }
            guard !cardState.canonicalConnectionExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionAlreadyExists
                )
            }
            return make(
                stage: .cardReflection,
                intent: .inviteCardConnection,
                next: question("cardRealityConnection", "connect_image_to_reality")
            )

        case .continueOpenCardConnection:
            try requireStage(.cardReflection)
            if let connection = memoryUpdate.cardRealityConnection?.normalizedConfirmed {
                guard connection.source == .userAuthored else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .cardConnectionSourceInvalid
                    )
                }
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: settingReflectionPhase(.exploratory),
                    action: .init(kind: .shareCardGuidance),
                    next: question(
                        "exploratoryReflection",
                        selfCriticismAttributionFocus
                    )
                )
            }
            let currentDifficulty = memoryUpdate.cardConnectionOutcome == .noConnectionFound
            guard cardState.substate == .openExploration || currentDifficulty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardSubstateMismatch
                )
            }
            guard !cardState.pendingCandidateExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateAlreadyPending
                )
            }
            guard !cardState.canonicalConnectionExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionAlreadyExists
                )
            }
            if currentDifficulty, !session.cardConnectionScaffoldUsed {
                // The Planner only said that this answer has not established a connection.
                // Swift owns the one protocol consequence: the first such outcome becomes the
                // single low-burden scaffold. No outcome kind or scaffold operation has to be
                // assembled by the model, and the same scaffold cannot be emitted twice.
                return make(
                    stage: .cardReflection,
                    intent: .developCardImage,
                    next: question("cardRealityConnectionScaffold", "narrow_connection_task")
                )
            }
            return make(
                stage: .cardReflection,
                intent: .inviteCardConnection,
                next: question("cardRealityConnection", "explore_connection")
            )

        case .offerCardConnectionScaffold:
            try requireStage(.cardReflection)
            if let connection = memoryUpdate.cardRealityConnection?.normalizedConfirmed {
                guard connection.source == .userAuthored else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .cardConnectionSourceInvalid
                    )
                }
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: settingReflectionPhase(.exploratory),
                    action: .init(kind: .shareCardGuidance),
                    next: question(
                        "exploratoryReflection",
                        selfCriticismAttributionFocus
                    )
                )
            }
            let currentDifficulty = memoryUpdate.cardConnectionOutcome == .noConnectionFound
            guard cardState.substate == .openExploration || currentDifficulty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardSubstateMismatch
                )
            }
            guard cardState.connectionDifficultyOccurred || currentDifficulty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionDifficultyMissing
                )
            }
            guard !cardState.bridgeScaffoldUsed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardScaffoldAlreadyUsed
                )
            }
            guard !cardState.pendingCandidateExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateAlreadyPending
                )
            }
            guard !cardState.canonicalConnectionExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionAlreadyExists
                )
            }
            return make(
                stage: .cardReflection,
                intent: .developCardImage,
                next: question("cardRealityConnectionScaffold", "narrow_connection_task")
            )

        case .offerCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard cardState.substate == .openExploration else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardSubstateMismatch
                )
            }
            guard cardState.candidateBridgeEligible else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateNotEligible
                )
            }
            guard let pending = memoryUpdate.pendingCardRealityConnection else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateMissing
                )
            }
            guard pending.isStructurallyComplete else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateIncomplete
                )
            }
            return make(
                stage: .cardReflection,
                intent: .inviteCardConnection,
                next: confirmation(
                    .cardRealityConnection,
                    referenceID: pending.id.uuidString
                )
            )

        case .establishUserAuthoredCardConnection:
            try requireStage(.cardReflection)
            guard session.condition.usesCard,
                  !session.cardConnectionUnavailable else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionUnavailable
                )
            }
            guard session.cardDisplayState == .displayed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardNotDisplayed
                )
            }
            guard !session.cardGuidanceShared else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardGuidanceAlreadyShared
                )
            }
            guard !cardState.pendingCandidateExists else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateAlreadyPending
                )
            }
            guard let connection = memoryUpdate.cardRealityConnection?.normalizedConfirmed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionMissing
                )
            }
            guard connection.source == .userAuthored else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionSourceInvalid
                )
            }
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: settingReflectionPhase(.exploratory),
                action: .init(kind: .shareCardGuidance),
                next: question(
                    "exploratoryReflection",
                    selfCriticismAttributionFocus
                )
            )

        case .acceptCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard let pending = session.semanticMemory.pendingCardRealityConnection else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateMissing
                )
            }
            guard pending.isStructurallyComplete else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateIncomplete
                )
            }
            var update = memoryUpdate
            update.cardRealityConnection = .init(
                imageRelation: pending.imageRelation,
                realityMapping: pending.candidateRealityMapping,
                source: .userAccepted
            )
            update.clearPendingCardRealityConnection = true
            update.cardConnectionOutcome = .connectionConfirmed
            update.candidateBridgeResolvedAt = Date()
            update.reflectionPhase = .exploratory
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: update,
                action: .init(kind: .shareCardGuidance),
                next: question("exploratoryReflection", selfCriticismAttributionFocus),
                resolved: .init(
                    target: .cardRealityConnection,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .reviseCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard let pending = session.semanticMemory.pendingCardRealityConnection else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateMissing
                )
            }
            guard pending.isStructurallyComplete else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateIncomplete
                )
            }
            guard let revision = memoryUpdate.cardRealityConnection?.normalizedConfirmed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionMissing
                )
            }
            guard revision.source == .userRevised else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionSourceInvalid
                )
            }
            var update = memoryUpdate
            update.clearPendingCardRealityConnection = true
            update.cardConnectionOutcome = .connectionConfirmed
            update.candidateBridgeResolvedAt = Date()
            update.reflectionPhase = .exploratory
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: update,
                action: .init(kind: .shareCardGuidance),
                next: question("exploratoryReflection", selfCriticismAttributionFocus),
                resolved: .init(
                    target: .cardRealityConnection,
                    decision: .revised,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .rejectCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard let pending = session.semanticMemory.pendingCardRealityConnection else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateMissing
                )
            }
            guard pending.isStructurallyComplete else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardCandidateIncomplete
                )
            }
            var update = memoryUpdate
            update.clearPendingCardRealityConnection = true
            update.cardConnectionOutcome = .candidateRejected
            update.candidateBridgeResolvedAt = Date()
            return make(
                stage: .cardReflection,
                intent: .inviteCardConnection,
                update: update,
                next: question("cardRealityConnection", "continue_after_rejected_candidate"),
                resolved: .init(
                    target: .cardRealityConnection,
                    decision: .rejected,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .bypassCardConnectionToDirectReflection:
            try requireStage(.cardReflection)
            guard session.cardConnectionUnavailable else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardBypassNotAuthorized
                )
            }
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: settingReflectionPhase(.exploratory),
                next: question("exploratoryReflection", selfCriticismAttributionFocus)
            )

        case .authorizeCardGuidance:
            try requireStage(.cardReflection)
            guard session.semanticMemory.cardRealityConnection?.normalizedConfirmed != nil else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardConnectionMissing
                )
            }
            guard !session.cardGuidanceShared else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .cardGuidanceAlreadyShared
                )
            }
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: settingReflectionPhase(.exploratory),
                action: .init(kind: .shareCardGuidance),
                next: question("exploratoryReflection", selfCriticismAttributionFocus)
            )

        case .presentLegacyCardReading:
            throw CurrentV5CoreError.projectionInvalid(
                operation: operation,
                failure: .legacyOperationUnavailable
            )

        case .continueExploratoryReflection:
            try requireStage(.directReflection)
            guard session.semanticMemory.reflectionPhase == .exploratory else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .reflectionPhaseMismatch
                )
            }
            if candidateHasGroundedSelfCriticismLink(memoryUpdate) {
                // The current act remains Exploration, while its phase-local completion outcome
                // carries the minimum LLM-authored Tender handoff. Swift establishes the canonical
                // frame and post-turn phase without relabeling the act as a Tender operation.
                var canonicalUpdate = memoryUpdate
                if hasReflectionContribution {
                    canonicalUpdate.reflectionFrame = try protocolShapedTenderFrame(
                        from: memoryUpdate
                    )
                } else {
                    // Decode-only compatibility for a saved/legacy current-v5 turn. New phase
                    // outcomes always supply the initial Tender delta atomically.
                    canonicalUpdate.reflectionFrame = nil
                }
                canonicalUpdate.reflectionPhase = .tender
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: memoryUpdate.contextCueOffered == true
                        ? question("contextRelationship", "assess_contextual_cue_relation")
                        : question(
                            "tenderReflection",
                            hasReflectionContribution
                                ? "respond_to_or_revise_bounded_tender_understanding"
                                : "form_first_bounded_tender_understanding"
                        )
                )
            }
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: settingReflectionPhase(.exploratory),
                next: memoryUpdate.contextCueOffered == true
                    ? question("contextRelationship", "assess_contextual_cue_relation")
                    : question("exploratoryReflection", selfCriticismAttributionFocus)
            )

        case .continueTenderReflection:
            try requireStage(.directReflection)
            guard session.semanticMemory.reflectionPhase == .tender else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .reflectionPhaseMismatch
                )
            }
            if session.semanticMemory.nextPrompt?.purpose == "contextRelationship",
               memoryUpdate.contextRelationship != nil {
                // A cue answer and the first Tender understanding belong to one semantic turn when
                // no Tender has yet been committed. This prevents Writer from speaking an
                // uncommitted Tender interpretation between two state transactions. Once Tender
                // already exists, the cue answer remains contextual evidence only.
                var canonicalUpdate = memoryUpdate
                canonicalUpdate.reflectionPhase = .tender
                if !CurrentV5CapabilitySet.hasCommittedTenderUnderstanding(in: session) {
                    canonicalUpdate.reflectionFrame = try protocolShapedTenderFrame(
                        from: memoryUpdate
                    )
                    return make(
                        stage: .directReflection,
                        intent: .directCandidReflection,
                        update: canonicalUpdate,
                        next: question(
                            "tenderReflection",
                            "respond_to_or_revise_bounded_tender_understanding"
                        )
                    )
                }
                canonicalUpdate.reflectionFrame = nil
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: question(
                        "tenderReflection",
                        CurrentV5CapabilitySet.hasCommittedTenderUnderstanding(in: session)
                            ? "resume_bounded_tender_understanding"
                            : "form_first_bounded_tender_understanding"
                    )
                )
            }
            if CurrentV5CapabilitySet.hasCommittedTenderUnderstanding(in: session),
               !hasReflectionContribution {
                // The phase-local outcome says the person's response still needs one bounded
                // clarification. Preserve the committed Tender frame and ask only that question;
                // absence of a new frame is not a malformed protocol transaction.
                var canonicalUpdate = memoryUpdate
                canonicalUpdate.reflectionFrame = nil
                canonicalUpdate.reflectionPhase = .tender
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: question(
                        "tenderReflection",
                        "clarify_current_bounded_tender_understanding"
                    )
                )
            }
            let frame = try protocolShapedTenderFrame(from: memoryUpdate)
            var canonicalUpdate = memoryUpdate
            canonicalUpdate.reflectionFrame = frame
            canonicalUpdate.reflectionPhase = .tender
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: canonicalUpdate,
                next: memoryUpdate.contextCueOffered == true
                    ? question("contextRelationship", "assess_contextual_cue_relation")
                    : question(
                        "tenderReflection",
                        "respond_to_or_revise_bounded_tender_understanding"
                    )
            )

        case .continueTenderGroundedFierceReflection:
            try requireStage(.directReflection)
            guard [.tender, .fierce].contains(session.semanticMemory.reflectionPhase) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .reflectionPhaseMismatch
                )
            }
            if session.semanticMemory.reflectionPhase == .tender {
                // Entering Fierce opens the inquiry; it does not require the answer to that inquiry
                // to have already been committed. Keep the grounded Tender frame in semantic memory
                // and let the next user answer form Protect/Provide/Repair/Motivate evidence.
                guard CurrentV5CapabilitySet.hasCommittedTenderUnderstanding(in: session),
                      !focus.isEmpty else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: focus.isEmpty
                            ? .responseFocusMissing
                            : .structuralPreconditionFailed
                    )
                }
                var canonicalUpdate = memoryUpdate
                if hasReflectionContribution {
                    canonicalUpdate.reflectionFrame = try protocolShapedTenderFrame(
                        from: memoryUpdate
                    )
                } else {
                    canonicalUpdate.reflectionFrame = nil
                }
                canonicalUpdate.reflectionPhase = .fierce
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: question(
                        "fierceReflection",
                        "discover_what_needs_protection_support_repair_or_change",
                        referenceID: inspectedRealityCandidateReference
                    )
                )
            }
            if session.semanticMemory.reflectionPhase == .fierce,
               !hasReflectionContribution {
                // This operation means "continue the current Fierce work", not "a complete Fierce
                // contribution must exist on every turn". When the latest answer has not yet
                // grounded, qualified, or declined a usable direction, keep the committed Tender
                // frame and the exact inspected candidate lineage. No semantic conclusion is
                // manufactured, and no protocol failure is exposed to the person.
                guard !focus.isEmpty else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .responseFocusMissing
                    )
                }
                var canonicalUpdate = memoryUpdate
                canonicalUpdate.reflectionFrame = nil
                canonicalUpdate.reflectionPhase = .fierce
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: question(
                        "fierceReflection",
                        "clarify_current_grounded_reality_direction",
                        referenceID: inspectedRealityCandidateReference
                    )
                )
            }
            let frame = try protocolShapedFierceFrame(from: memoryUpdate)
            guard doesNotReuseInvalidatedInterpretation(frame, update: memoryUpdate) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .rejectedInterpretationReused
                )
            }
            var canonicalUpdate = memoryUpdate
            canonicalUpdate.reflectionFrame = frame
            // This turn performed and validated the Fierce contribution. Its merged candidate
            // state completes Fierce, so only the post-turn phase advances; the current operation
            // is not relabeled and no Synthesis content is invented.
            canonicalUpdate.reflectionPhase = .synthesis
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: canonicalUpdate,
                next: question(
                    "synthesisReflection",
                    "synthesize_grounded_fierce_direction"
                )
            )

        case .synthesizeDirectReflection:
            try requireStage(.directReflection)
            guard [.tender, .fierce, .synthesis].contains(
                session.semanticMemory.reflectionPhase
            ) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .reflectionPhaseMismatch
                )
            }
            if session.semanticMemory.reflectionPhase != .synthesis {
                guard CurrentV5CapabilitySet.hasCommittedSynthesisBasis(in: session) else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .structuralPreconditionFailed
                    )
                }
            }
            if session.semanticMemory.reflectionPhase == .synthesis,
               session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding,
               !hasReflectionContribution,
               reflectionProgressionMeaning == .clarifySynthesis {
                // A phase-local clarification outcome keeps the committed Synthesis intact. It
                // does not require the Planner to serialize the same frame again.
                var canonicalUpdate = memoryUpdate
                canonicalUpdate.reflectionFrame = nil
                canonicalUpdate.reflectionPhase = .synthesis
                return make(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    update: canonicalUpdate,
                    next: question(
                        "synthesisReflection",
                        "clarify_current_synthesis"
                    )
                )
            }
            let frame = try protocolShapedSynthesisFrame(from: memoryUpdate)
            var canonicalUpdate = memoryUpdate
            canonicalUpdate.reflectionFrame = frame
            canonicalUpdate.reflectionPhase = .synthesis
            return make(
                stage: .directReflection,
                intent: .directCandidReflection,
                update: canonicalUpdate,
                next: question(
                    "synthesisReflection",
                    "confirm_or_revise_synthesis"
                )
            )

        case .proposePractice:
            try requireStage(.directReflection, .narrativeConfirmation, .optionalAction)
            guard let transition = memoryUpdate.practiceTransition,
                  let proposal = transition.proposal else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceProposalMissing
                )
            }
            let content = proposal.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let basis = proposal.basis.trimmingCharacters(in: .whitespacesAndNewlines)
            guard transition.noActionReason == nil,
                  !content.isEmpty,
                  !basis.isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceProposalIncomplete
                )
            }
            guard !transition.transactionID.isEmpty,
                  proposal.id == transition.transactionID,
                  proposal.status == .pendingConfirmation,
                  proposal.source == .assistantProposed else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceProposalIncomplete
                )
            }
            let grounding = CurrentV5GroundedRealityCandidate.projected(
                from: session.semanticMemory,
                applying: memoryUpdate
            )
            guard grounding.contains(where: { $0.id == basis }) else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceEvidenceInvalid
                )
            }
            return make(
                stage: .optionalAction,
                intent: .suggestPractice,
                update: memoryUpdate,
                next: confirmation(.practice, referenceID: transition.transactionID),
                resolved: sourceStage == .narrativeConfirmation
                    ? .init(
                        target: .finalNarrative,
                        decision: .accepted,
                        referenceID: transition.narrativeReferenceID
                    )
                    : nil
            )

        case .resolvePractice:
            try requireStage(.optionalAction)
            guard let activeTransition = session.semanticMemory.practiceTransition,
                  let activeProposal = activeTransition.proposal else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .activePracticeMissing
                )
            }
            guard let transition = memoryUpdate.practiceTransition else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceResolutionMissing
                )
            }
            let resolution: TurnConfirmationDecision
            let resolvedPracticeContent: String?
            if let noActionReason = transition.noActionReason {
                _ = noActionReason
                resolution = .declined
                resolvedPracticeContent = nil
            } else if let proposed = transition.proposal {
                let content = proposed.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let basis = proposed.basis.trimmingCharacters(in: .whitespacesAndNewlines)
                guard transition.transactionID == activeTransition.transactionID,
                      proposed.id == activeProposal.id,
                      proposed.status == .confirmed else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .practiceResolutionMissing
                    )
                }
                let revised = proposed.source == .userRevised
                if revised {
                    guard !content.isEmpty, !basis.isEmpty else {
                        throw CurrentV5CoreError.projectionInvalid(
                            operation: operation,
                            failure: .practiceProposalIncomplete
                        )
                    }
                    guard CurrentV5GroundedRealityCandidate.projected(
                        from: session.semanticMemory,
                        applying: memoryUpdate
                    ).contains(where: { $0.id == basis }) else {
                        throw CurrentV5CoreError.projectionInvalid(
                            operation: operation,
                            failure: .practiceEvidenceInvalid
                        )
                    }
                    resolution = .revised
                    resolvedPracticeContent = content
                } else {
                    resolution = .accepted
                    resolvedPracticeContent = activeProposal.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .practiceResolutionMissing
                )
            }
            guard let synthesis = session.semanticMemory.reflectionFrame,
                  synthesis.action == .synthesizeUnderstanding,
                  !synthesis.reflectionDelta
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .finalNarrativeMissing
                )
            }
            let practiceLine = resolvedPracticeContent.map {
                "接下来愿意尝试：\($0)"
            } ?? "这次没有加入新的行动。"
            var canonicalUpdate = memoryUpdate
            // Planner decides the Synthesis meaning and Action transaction. Swift owns the one
            // protocol shape that combines those committed components; a fresh Planner-authored
            // narrative string is deliberately ignored.
            canonicalUpdate.finalNarrative = [
                synthesis.reflectionDelta.trimmingCharacters(in: .whitespacesAndNewlines),
                practiceLine,
            ].joined(separator: "\n")
            return make(
                stage: .narrativeConfirmation,
                intent: .presentFinalNarrative,
                update: canonicalUpdate,
                next: confirmation(.finalNarrative),
                resolved: .init(
                    target: .practice,
                    decision: resolution,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .confirmNarrative:
            try requireStage(.directReflection, .narrativeConfirmation, .optionalAction)
            let narrative = memoryUpdate.finalNarrative ?? session.semanticMemory.finalNarrative
            guard narrative?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .finalNarrativeMissing
                )
            }
            return make(
                stage: .narrativeConfirmation,
                intent: .presentFinalNarrative,
                next: confirmation(.finalNarrative)
            )

        case .reviseNarrative:
            try requireStage(.narrativeConfirmation)
            guard memoryUpdate.finalNarrative?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw CurrentV5CoreError.projectionInvalid(
                    operation: operation,
                    failure: .finalNarrativeRevisionMissing
                )
            }
            return make(
                stage: .narrativeConfirmation,
                intent: .reviseFinalNarrative,
                next: confirmation(.finalNarrative)
            )

        case .completeConversation:
            try requireStage(.narrativeConfirmation, .optionalAction, .complete, .safetySupport)
            let resolved: TurnResolvedConfirmation?
            if sourceStage == .narrativeConfirmation {
                guard session.semanticMemory.nextPrompt?.target == .finalNarrative else {
                    throw CurrentV5CoreError.projectionInvalid(
                        operation: operation,
                        failure: .activeNarrativeConfirmationMissing
                    )
                }
                resolved = .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            } else {
                resolved = nil
            }
            return make(
                stage: .complete,
                intent: .completeConversation,
                action: .init(kind: .completeSession),
                resolved: resolved
            )

        case .provideSafetySupport:
            return make(
                stage: .safetySupport,
                intent: .safetySupport,
                update: TurnSemanticMemoryUpdate()
            )
        }
    }
}
