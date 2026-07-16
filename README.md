# Beyond Comfort

An iOS 17+ SwiftUI research prototype for state-machine-guided self-compassion reflection. The app runs end-to-end with a deterministic mock model when no API key is present.

## Run

Open `BeyondComfort.xcodeproj`, choose an iOS 17+ device, and run. The app requests Health and Calendar read access at launch. A real device is required for the user's actual Health data.

## DeepSeek configuration

Set the generated Info.plist build settings `INFOPLIST_KEY_DEEPSEEK_API_KEY` and `INFOPLIST_KEY_DEEPSEEK_MODEL`, preferably through a local, git-ignored `.xcconfig`. The default model is `deepseek-v4-flash`. Never ship a research or production app with a provider key embedded; use a server-side proxy.

## Card art

`CardService` owns 22 visual source cards and performs a uniform random draw. The UI crops the printed title/number region, exposes only a neutral `Reflection Card NN` label, and never sends the source identity or conventional symbolism to the LLM. The model receives only the user's interpretation after the user has responded. The bundled scans come from [`metabismuth/tarot-json`](https://github.com/metabismuth/tarot-json); license details are retained at `Resources/Tarot/SOURCE_LICENSE.txt`.

## Required permission requests

- HealthKit: the project includes the HealthKit entitlement and `NSHealthShareUsageDescription`; do not add a write/update usage key. At launch the app requests read access for sleep analysis, resting heart rate, and HRV (SDNN). At context confirmation it compares the event-day window against the preceding 30-day personal baseline.
- EventKit: no capability is needed. Keep `NSCalendarsFullAccessUsageDescription`; the implementation only counts event durations and never reads or displays titles/notes.

The app always requests both integrations, but iOS still gives the person final control. If access is denied or data is unavailable, the reflection remains usable and reports that no observations were found.

## Research instrumentation

Each session is stored separately and records timestamped state transitions, condition, confirmed context, card interpretation, hypothesis decisions, selected action, and six 1–7 manipulation/outcome checks (felt understanding, compassionate candor, reactance, responsibility clarity, interpretation ownership, and prior card familiarity). Review Close can export one pseudonymous JSON record. No event titles, notes, raw HealthKit samples, API keys, names, or contact identifiers are added by the app, but researchers must still treat user-authored free text as potentially identifying.

## Experimental condition

Change `ReflectionSession.condition` from `.cardMediated` to `.modelAsserted`. The latter preserves context/tender/action/review stages and bypasses card stages for a direct hedged hypothesis.

## Structure

- `Models`: session, canvas, card, hypothesis, action, and message types
- `ViewModels`: explicit Swift-owned `ReflectionStage` transitions
- `Views` / `ContentView.swift`: chat and inline interactive panels
- `Services`: DeepSeek/Mock LLM, cards, HealthKit, EventKit, safety, local JSON storage
