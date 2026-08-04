# Beyond Comfort engineering rules

- Swift application code owns every reflection-state transition. LLM output may suggest analysis or wording, but it must not advance the workflow, select a card, or assign responsibility.
- Keep context analysis and user-facing dialogue generation as separate typed interfaces. Validate structured output and preserve uncertainty on failure.
- Treat HealthKit, EventKit, screen-time, and weather records as optional contextual cues—not causal, diagnostic, psychological, or moral evidence. Only user-confirmed relevant insights enter later prompts.
- Calculate tracking metrics deterministically from cleaned daily records and personal baselines. Never treat missing observations as zero or send raw health samples to an LLM.
- Select reflection cards locally and independently of route, emotion, tracking data, and model recommendations. The user interprets the image before the assistant connects it to their situation.
- Tender/fierce route names, scores, reason codes, prompt text, and workflow states are internal and must not appear in the UI.
- Centralize current TurnController prompts in the versioned backend `prompt_registry`; the iOS app
  sends only typed context plus an immutable prompt version. Keep non-Turn legacy prompts in
  `ReflectionPromptFactory`, and never place long prompt strings in views or view models.
- Do not log API keys, authorization headers, complete personal reflections, raw health records, or unredacted LLM bodies in production.
- Preserve existing sessions through additive Codable defaults and safe server migrations; never delete stored research data to simplify a schema change.
- Before claiming completion, run the relevant Swift unit tests, an iOS simulator build, and backend tests when backend code changes.
