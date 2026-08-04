# Optional Action Protocol Inventory

This inventory records the practice protocol before consolidation. Classifications:

- **A — Current:** required by the formal one-proposal Optional Action flow.
- **B — Migration only:** historical decode/export input that must normalize before runtime.
- **C — Superseded runtime:** replaced by the current flow but still read or written.
- **D — Test only:** retained by an obsolete fixture or assertion.
- **E — Duplicate truth source:** independently represents state already owned elsewhere.
- **F — Dead/unreachable:** cannot be reached by a new current TurnController session.
- **G — Legacy multi-choice:** conflicts with the one-proposal product contract.

## Current operations

| Symbol | Class | Disposition |
|---|---:|---|
| `narrativeConfirmation` | A | Final narrative is awaiting one typed resolution. |
| `optionalAction` | A | Exactly one pending proposal may be shown and negotiated. |
| `suggestPractice` | A | Creates the one complete proposal after narrative acceptance. |
| `revisePractice` | A | Replaces the pending proposal with the person's bounded revision. |
| `completeConversation` | A | Commits accepted/revised practice or a formal no-action outcome. |
| `TurnPracticeKind` | A | Closed care/repair/protect/change/noAction category. |
| `TurnNoActionReason` | A | Closed evidence-bounded reason for completing without a proposal. |
| `nextPrompt.target=practice` | A | Typed pending confirmation for the one proposal. |

## Competing practice state

| Symbol | Class | Evidence and disposition |
|---|---:|---|
| `TurnPracticeOption` | C/G | Array element from the retired menu design; `basis` is optional even though current validation requires it. Replace with one canonical proposal. |
| `practiceOptions` | C/E/G | Runtime array despite the current maximum of one. Move to legacy decode only. |
| `practiceKind` | C/E | Separate pending/selected/noAction truth source. Fold into the canonical transition. |
| `selectedPractice` | C/E | String copy of an option instruction. Replace with proposal status/source. |
| `finalNarrativeConfirmed` | B/E | Coarse pre-Turn workflow mirror. It must not determine current Turn progression. |
| `userAuthoredActionConfirmed` | B/E | Coarse pre-Turn workflow mirror. It must not become current practice truth. |
| `pendingUserAuthoredAction` | B | Pre-Turn/direct-condition state outside the current Turn protocol. |

## Validation and normalization

| Item | Class | Disposition |
|---|---:|---|
| option-count, duplicate-ID and noAction-option checks | C/G | Several checks around the retired array. Replace with one proposal validator. |
| basis non-empty check | A/E | Correct current requirement, but currently separate from stage/intent/prompt validation. Centralize it. |
| stage/intent transition table | A | Retain and make subordinate to the atomic practice transition validator. |
| `confirmationTargetEstablished(.suggestPractice)` | A | Retain only as typed intent classification; the canonical validator rejects missing or mismatched proposal IDs instead of inventing them. |
| accepted instruction-to-kind lookup | C/E/G | Reads the retired option catalogue. Delete. |
| selected instruction equality check | C/E/G | Second selection truth source. Delete. |
| `missingPracticeOptions` / `missingPracticeKind` warnings | C | Old soft-admission behavior; delete. |
| `missingRequiredMemoryField(.practiceBasis)` | C/E | First-error-only view of a cross-field failure. Replace with one typed incomplete-transition error family. |

## Recovery ownership

| Item | Class | Disposition |
|---|---:|---|
| ordinary regeneration | C/E | First generic owner of the same incomplete proposal. Remove for this error family. |
| generic continuity recovery | C/E | Second owner; may replan the whole semantic turn. Remove for this error family. |
| user-visible retry planner | C/E | Re-parses the already accepted narrative. Replace with idempotent pending-transition resume. |
| Writer retry | A | Retain only after one complete proposal plan has passed validation. |
| provider availability fallback | A | Operational fallback, not a proposal truth source; keep outside practice semantics. |

## Prompt and schema

| Item | Class | Disposition |
|---|---:|---|
| one small grounded practice instruction | A | Retain. |
| normal Planner skeleton with `practiceOptions:null` | C/G | Does not expose the required object shape. Replace with canonical proposal schema. |
| JSON repair description containing `basis` | C/E | More complete than the normal contract. Align both to one schema. |
| Plan Critic practice evidence audit | A | Retain, but audit the canonical proposal only. |

## Canonical replacement

The current runtime will persist one practice transition transaction. It records that the final
narrative confirmation has been consumed and then holds either one complete pending/confirmed
proposal or one typed no-action outcome. Proposal identity, kind, user-visible content, evidence
basis, status, and source are atomic. All capability, validation, progression, recovery, resume,
and confirmation code must read one effective transition projection.

The old option array, selected instruction, and independent kind remain readable only by a legacy
decoder. An incomplete legacy option is never promoted into a current pending proposal.
