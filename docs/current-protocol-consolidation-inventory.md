# Current Protocol Consolidation Inventory

This inventory records the runtime protocol immediately before consolidation. Classifications:

- **A — Current:** required by the formal current product flow.
- **B — Migration only:** historical decode/export input that must normalize before runtime.
- **C — Superseded runtime:** replaced by the current flow but still read by production code.
- **D — No production reader:** written or declared without a current runtime consumer.
- **E — Test only:** retained only by an obsolete fixture or assertion.
- **F — Duplicate:** a second implementation of an existing canonical rule.
- **G — Dead:** unreachable from a new current session.

## Stages

| Symbol | Class | Evidence and disposition |
|---|---:|---|
| `contextualDisclosure` | A | Current card-session entry; gathers only focal event, process, and behavior/omission. |
| `cardConsent` | A | Current successor when disclosure core is complete. |
| `cardReflection` | A | Current local-card observation, connection, and guidance flow. |
| `directReflection` | A | Current post-card candid reflection. |
| `narrativeConfirmation` | A | Current final narrative confirmation. |
| `optionalAction` | A | Current one-practice proposal/negotiation. |
| `complete` | A | Current terminal stage. |
| `safetySupport` | A | Current safety interrupt. |
| `tenderConfirmation` | B/C/G | Historical separate Tender approval stage. New card sessions bypass it; the current direct-control condition bypasses the Turn protocol entirely. Migrate saved values, then remove runtime transitions/readers. |

## Disclosure purposes

| Symbol | Class | Disposition |
|---|---:|---|
| `identifyConcreteEpisode` | A | Current focal-event question. |
| `clarifyEventProcess` | A | Current event-development question. |
| `clarifyBehavior` | A | Current action/omission question. |
| `clarifyImmediateOutcome` | B/E/G | Legacy decode value; actual impact is optional and cannot gate progression. |
| `clarifyReflectionFocus` | B/C/E | Legacy decode value; reflection focus is optional and cannot gate progression. |

## Semantic memory

| Group | Class | Disposition |
|---|---:|---|
| `episodeStructure.concreteFacts`, `eventProcessStatus`, `behaviorEvidenceStatus`, `behaviorEvidence` | A | Canonical disclosure evidence. |
| Optional episode contributors, constraints, controllable parts, impacts, uncertainty | A | Retain as non-gating evidence for later reflection. |
| `eventDisclosureOutcome` | A | Planner summary; validation must be subordinate to canonical effective core state. Retired raw `needsReflectionFocus` migrates to a current value. |
| `nextPrompt`, received/answered current disclosure purposes | A | Current typed interaction state. |
| `selfCriticismStatus`, `selfCriticalStatement`, `selfCriticismLink` | A optional | May preserve volunteered material; never gates Event Disclosure or Card Consent. |
| `reflectionFocusKind`, `reflectionFocus` | B/C | Historical pre-card routing metadata. Remove from current Planner/Writer/validation; legacy payload keys decode only at migration boundary. |
| `tenderGroundingKind` | B/C/E | Historical Planner–Swift handshake that caused the reported failure. Remove from schema and runtime. |
| `tenderUnderstanding` | B/C | Historical separate Tender confirmation content. Remove with the retired stage; old payload key remains ignorable/migratable. |
| legacy pending question/confirmation fields | B | Decode/migration only; current interaction uses `nextPrompt`. |
| canonical `cardRealityConnection` and pending canonical connection | A | Current post-card flow; outside this refactor. |
| retired scalar card connection fields | B | Existing migration boundary only; outside this refactor. |
| context/tracking relationship fields | A/B | Tracking behavior is outside this task; do not broaden cleanup into tracking semantics. |
| candid, narrative, and practice memory | A | Current later flow; outside this refactor. |

## Capabilities and transitions

| Item | Class | Disposition |
|---|---:|---|
| `exploreContext` with one of the three current purposes | A | Available only while canonical disclosure core is incomplete. |
| `inviteCardConsent` | A | The sole normal successor once canonical disclosure core is complete. |
| local `drawRandomCard` | A | Swift-owned local action after accepted consent. |
| Tender-summary intents and transitions | C/G | Remove from current Turn protocol. |
| legacy tracking presentation/confirmation intents | B | Do not modify tracking in this task; ensure they cannot become disclosure completion gates. |

## Validation and errors

| Item | Class | Disposition |
|---|---:|---|
| structural stage/intent/action/next-prompt validation | A | Retain. |
| canonical episode-core validation | A | Centralize behind one effective state and one completion function. |
| `disclosureShouldAdvance` | A | Retain only as over-exploration signal and recover directly to Card Consent from canonical state. |
| reflection-focus/Tender-kind pairing | C | Delete. |
| `missingRequiredMemoryField(.tenderGroundingKind)` | C | Delete field/error path. |
| current Card Consent requirement for `eventDisclosureOutcome == ready...` | F | Outcome is Planner metadata, not a second completion truth; normalize/validate from canonical state. |
| v3 `missingCurrentDisclosureEvidenceField`/Tender evidence gate | B/C | Isolate to migration or delete after saved-session normalization. |

## Recovery and fallback

| Item | Class | Disposition |
|---|---:|---|
| bounded provider/Writer availability fallback | A | Not a protocol-completion rule; retain outside this scope. |
| protocol correction for malformed structural plans | A | Retain, but it must consume canonical disclosure state. |
| forward recovery for disclosure over-exploration | A/F | Retain one direction only: complete core → Card Consent. Delete duplicated completion logic and Tender repair. |
| continuity recovery for missing Tender metadata | C | Delete by removing the error and credential. |
| bounded disclosure fallback's hand-built completion predicate | F | Replace with the canonical effective disclosure state. |

## Confirmation targets

| Symbol | Class | Disposition |
|---|---:|---|
| `cardConsent`, `cardRealityConnection`, `cardMapping`, `finalNarrative`, `practice` | A | Current flow. |
| `tenderSummary` | B/C/G | Retired separate Tender approval; migrate saved pending prompt and remove runtime generation/readers. |
| `trackingRelationship` | B/A | Tracking-specific compatibility is outside this task. |

## Prompt, Critic, and JSON repair

| Rule | Class | Disposition |
|---|---:|---|
| Three-relation disclosure contract | A | Retain and make authoritative. |
| Duplicate/reopened/ignored-answer/unsupported-premise/over-exploration checks | A | Retain. |
| Tender-kind pairing table and missing-Tender repair | C | Delete. |
| legacy purpose catalogue/examples | C/E | Delete from current Prompt and strict JSON repair. |
| Tender-stage Writer and Critic contracts | C/G | Delete after legacy session normalization. |

## Canonical replacement

All runtime readers will use one `EffectiveEventDisclosureState`, created by applying a typed
memory patch once to stored semantic memory. One `isEventDisclosureCoreComplete` function will read
only:

1. a non-empty focal event;
2. a resolved, user-grounded event process;
3. a resolved, non-empty user behavior or omission.

No Tender, reflection-focus, impact, emotion, importance, guilt, or self-judgment metadata may
participate in capability generation, validation, stage progression, recovery, or fallback.
