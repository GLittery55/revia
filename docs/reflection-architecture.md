# Reflection architecture

## Conversation control

`ReflectionViewModel` and `ReflectionStateMachine` own the research flow. The model may analyze the
latest message and generate wording inside the current state, but it cannot advance the workflow,
select a card, confirm a tracking cue, accept an action, or complete a session.

The card-mediated condition follows one bounded backbone:

```text
structured disclosure (3–5 assistant turns)
→ tender grounding and correction
→ automatic review of at most one already-authorized tracking cue
→ correctable context summary
→ local random card draw and verified display
→ card observation
→ at most one image-only association question
→ optional card-to-life connection (at most two invitations)
→ tender circumstances reflection
→ candid agency / boundary / change reflection
→ integrated narrative accuracy check
→ optional user-authored small action
→ final narrative accuracy check
→ complete
```

Structured disclosure stops when the conversation contains a bounded event, an emotion or bodily
experience, a self-appraisal or personal meaning, and at least one real constraint, conflict, or
coping response. It does not keep collecting technical details after these are clear. Three turns are
a minimum for a normal full path and five are the upper bound; unknown information remains unknown.

Tender grounding comes before tracking. It distinguishes the concrete situation from a global
self-label without declaring the label false, excusing behavior, or assigning responsibility. The
user's next response may confirm or correct that distinction.

After tracking, a short context summary combines only disclosed facts, the corrected grounding, and
tracking relevance the user confirmed or qualified. The user can correct it before a card is drawn.
Internal state names, counters, routes, scores, and process rules never appear in visible dialogue.

Each typed user message has one stable turn identifier and may own at most one visible assistant
reply. State transitions wait for the user's answer; an automatic transition never emits a second
assistant message for the same user turn.

Legacy sessions remain readable through additive `Codable` defaults and legacy state-name mapping.
The backend stores the version-tolerant session payload as PostgreSQL JSON, so additive fields do not
require a destructive migration.

## Model boundaries

`ContextAnalyzing` and `DialogueGenerating` are separate typed interfaces. Analysis returns validated
structured evidence and uncertainty; it does not produce visible text or mutate application state.
Dialogue generation receives the application-selected state, one turn purpose, confirmed context,
at most one eligible tracking cue, optional locally selected card, and recent history.

`ReflectionPromptFactory` centralizes all prompts. The server Planner and Critic enforce the same
contracts, but remain advisory: they plan and review a single reply, not the session. Malformed output
is rejected or repaired without inventing evidence or changing state.

Visible replies use short, ordinary Chinese, normally one grounded response and at most one easy
question. They follow the user's latest answer and avoid interview-like field collection, ornate
phrases, repeated paraphrases, hidden-motive claims, diagnostic language, workflow announcements,
and premature advice.

## Self-tracking pipeline

HealthKit and EventKit authorization happens outside the reflective attribution flow. Once authorized,
the app does not interrupt the conversation with another all-or-nothing tracking permission menu.
At the fixed point after tender grounding it may automatically present at most one deterministic,
eligible cue. If access is absent, data are incomplete, or no cue is useful, the phase is silently
skipped.

The data pipeline remains deterministic:

1. Retrieval preserves provenance and authorization metadata.
2. One source is selected deterministically; overlapping sleep intervals are merged.
3. Daily values remain optional and missing days are never converted to zero.
4. The recent seven-day window is compared with the preceding personal baseline using robust
   statistics and minimum-coverage rules.
5. The result is a neutral observation with limitations and alternative explanations.
6. The user says in ordinary language whether the tentative connection fits. Only relevant,
   user-confirmed context may enter later prompts; uncertainty remains explicit.

Tracking can describe background capacity or load. It cannot establish cause, diagnosis, motive,
morality, responsibility, avoidance, stress, or why a task did not progress. Raw health samples are
never sent to the model.

## Card flow

`CardService` draws locally by uniform chance and accepts no route, emotion, tracking value, or model
recommendation. The selected card ID is persisted before loading. The assistant asks about the image
only after the UI confirms that this exact image displayed successfully.

If loading fails, retry reloads the same selected card. It does not draw a replacement or turn the
failure into reflective material. A deliberate new draw is a separate user action outside a failed
load retry.

The user first describes what appears to be happening. The assistant may ask at most one follow-up
using only a detail, uncertainty, or changed judgment the user named. Neither question connects the
image to real life. A later invitation asks whether the user's own image narrative brings part of the
real situation to mind.

A vague fit such as “有点像” is not a connection and receives one concrete clarification. If the user
cannot or does not want to connect the card, one optional scaffold is the maximum; a second “没有” or
“想不到” ends card connection. `card_connection: none` is a valid research result. The app does not
redraw until a card happens to fit, invent a connection, or continue probing.

## Candid reflection, action, and completion

With a user-authored card connection, candid reflection has two ordered exchanges:

1. the user identifies circumstances, limits, or pain that should be acknowledged;
2. the user identifies any agency, boundary, repair, or change they still consider available.

The assistant never supplies the verdict. After both answers it writes one coherent narrative from
confirmed material and asks what is inaccurate. Corrections are incorporated before action appears.

An action is optional and begins with the user's own direction. It may be categorized as care,
protection, provision, repair, or change, then made small enough for the user's actual conditions.
No action is stored until the user explicitly accepts its wording; declining is a complete outcome.

The final narrative contains only confirmed disclosure, relevant tracking background with uncertainty,
the user's card interpretation and connection, the user's own tender/candid distinctions, and an
accepted action if one exists. The session completes only after the user confirms this narrative or a
corrected version. A nominal complete path takes roughly 10–16 assistant turns; counters and terminal
branches prevent repeated probing from extending it indefinitely.

## Privacy, safety, and failure behavior

Users can delete individual sessions, tracking cues, or all reflection data through existing local and
cloud flows. Production logs contain metadata only and never API keys, authorization headers, complete
reflections, raw health data, or unredacted model bodies.

Immediate self-harm or imminent-danger language interrupts the ordinary workflow and enters isolated
`safetySupport`. Provider or structured-output failures retain the user's message and current state,
offer a retry, and never fabricate analysis or silently advance the session.
