# Agents.md — Coyote Agent Definitions

This document defines every autonomous agent (module/component) in the Coyote project, its responsibility, inputs, outputs, and the exact file it lives in.

---

## Agent 1: App Shell (`CoyoteApp`)

**File**: `Coyote/CoyoteApp.swift` (29 lines)

**Responsibility**: The `@main` entry point. Creates the single window, injects the ViewModel, enforces dark mode, hidden title bar, and removes the default "New Window" menu command.

**Inputs**: None (launched by macOS).

**Outputs**: A `WindowGroup` containing `ContentView` with `CaptionBarViewModel` as an `EnvironmentObject`.

**Key Behaviors**:
- `@NSApplicationDelegateAdaptor(AppDelegate.self)` — `AppDelegate` calls `NSApp.activate(ignoringOtherApps: true)` on launch.
- `@StateObject private var viewModel = CaptionBarViewModel()` — single source of truth.
- Window scene modifiers: `.defaultSize(width: 860, height: 500)`, `.windowStyle(.hiddenTitleBar)`, `.windowResizability(.contentMinSize)`.
- `CommandGroup(replacing: .newItem) { }` — removes File > New Window.
- `.preferredColorScheme(.dark)` on ContentView.

**Dependencies**: `ContentView`, `CaptionBarViewModel`.

**Imports**: `AppKit`, `SwiftUI`.

---

## Agent 2: Environment Loader (`Env`)

**File**: `Coyote/EnvLoader.swift` (52 lines)

**Responsibility**: Loads API keys from a `.env` file at launch. Searches three candidate paths in order: next to the app bundle, up through DerivedData to the project root, and a hardcoded Desktop fallback.

**Inputs**: A `.env` file containing `OPENAI_API_KEY`, `CLAUDE_API_KEY`, `CRUSTDATA_API_TOKEN`.

**Outputs**: Static computed properties: `Env.openAIKey`, `Env.claudeAPIKey`, `Env.crustdataToken`.

**Key Behaviors**:
- `private static let values: [String: String]` — lazily loaded dictionary.
- `parse(_ contents: String)` — splits on `=`, trims whitespace, skips comments (`#`) and blank lines.
- Candidate paths:
  1. `Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env")`
  2. Navigate up 4 levels from bundle (through DerivedData) + `.env`
  3. `~/<YOUR_PROJECT_PATH>/coyote/.env` (hardcoded fallback — update path for your environment)

**Dependencies**: `Foundation`.

---

## Agent 3: ViewModel (`CaptionBarViewModel`)

**File**: `Coyote/CaptionBarViewModel.swift` (368 lines)

**Responsibility**: The central `@MainActor ObservableObject` that owns all UI state, manages permissions, drives the capture lifecycle, routes transcripts to the intelligence engine, and positions the floating window.

**Inputs**: User actions (start/stop/reset/edit/remove), `TranscriptUpdate` from `LiveMeetingCapture`, audio levels.

**Outputs**: Published properties consumed by `ContentView`: `captionPanel`, `statusMessage`, `detailMessage`, `isRunning`. Also exposes `intelligenceEngine` directly.

### Data Models (defined in this file)

```swift
struct CaptionEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp = Date()
}

struct TranscriptPanelState {
    let title: String          // "Live Captions"
    let icon: String           // "waveform.badge.mic"
    let placeholder: String    // "Mic + system audio captions appear here…"
    var liveText = ""
    var finalized: [CaptionEntry] = []
    var level: Double = 0.02
}
```

### Published State
- `captionPanel: TranscriptPanelState`
- `statusMessage: String` — "Ready for live captions" initially
- `detailMessage: String` — permission/status detail
- `isRunning: Bool`
- `intelligenceEngine: IntelligenceEngine` — `let`, not `@Published`; changes forwarded via Combine sink

### Private State
- `captureController: LiveMeetingCapture`
- `window: NSWindow?` (weak)
- `levelDecayTask: Task<Void, Never>?`
- `screenObserver: NSObjectProtocol?`
- `requiresScreenCaptureRegrant: Bool`
- `intelCancellable: Any?` (Combine `AnyCancellable`)
- `hasPositioned: Bool`

### Initialization
1. `bindCaptureCallbacks()` — wires `onTranscript`, `onLevel`, `onStatus`, `onError` from capture controller.
2. `intelCancellable` — `intelligenceEngine.objectWillChange.sink` that forwards to `self.objectWillChange.send()` on MainActor.
3. Screen parameter observer — `NSApplication.didChangeScreenParametersNotification` (no-op handler, keeps window where user placed it).
4. Level decay task — `Task` loop every 60ms, multiplies level by 0.82, floors at 0.02.

### Window Configuration (`configure(window:)`)
- `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
- `level = .floating`, `isMovableByWindowBackground = true`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]`
- Style masks: `.titled`, `.fullSizeContentView`, `.closable`, `.miniaturizable`, `.resizable`
- First-time positioning: `positionWindowAtBottom` — width = `min(max(visibleFrame.width * 0.68, 860), 1080)`, height = `min(680, visibleFrame.height - 80)`, origin at `(midX - width/2, minY + 60)`.

### Capture Lifecycle
- `toggleCapture()` — delegates to `startCapture()` or `stopCapture()`.
- `startCapture()` — resets panels, checks permissions (`requestPermissions()`), starts capture controller, updates status messages. On error: sets `statusMessage = "Unable to start"`.
- `stopCapture()` — `await captureController.stop()`, `isRunning = false`.
- `terminateApp()` — stops capture then `NSApp.terminate(nil)`.

### Permissions (`requestPermissions() async throws -> PermissionSnapshot`)
- `requestSpeechAuthorization()` — `SFSpeechRecognizer.requestAuthorization`.
- `requestMicrophoneAccess()` — `AVAudioApplication.shared.recordPermission` / `requestRecordPermission`.
- `screenCaptureAccessStatus()` — `CGPreflightScreenCaptureAccess()`.
- Returns `PermissionSnapshot(speechAuthorized:, microphoneAuthorized:, screenCaptureAuthorized:)`.

### Transcript Routing (`applyTranscript(_ update: TranscriptUpdate)`)
- `isFinal == true`: clears `liveText`, calls `intelligenceEngine.processFinalizedCaption(cleaned)`.
- `isFinal == false`: sets `liveText`. If > 150 chars, truncates to last 150 at word boundary with "…" prefix.

### Level Metering
- `applyLevel`: `max(current, clamp(level, 0.02...1.0))`.
- `decayLevels`: `level * 0.82`, floor 0.02.

### Caption Logging
- Logs to `~/Coyote-Captions.log` with format `[ISO8601] [FINAL/PARTIAL] text`.

### Entity Chip Delegation
- `removeEntityChip(_ entry:)` → `intelligenceEngine.removeEntity(named:)`
- `editEntityChip(_ entry:, newText:)` → `intelligenceEngine.editEntity(oldName:, newName:)`
- `resetAll()` → clears panel state + `intelligenceEngine.reset()`

### Error Handling
- `describe(_ error:)` — `"\(error.localizedDescription) [\(nsError.domain) \(nsError.code)]"`
- `requiresScreenCaptureRegrant(for:)` — checks for `CaptureError.screenRecordingPermissionOutOfSync`, `PermissionError.screenRecording`, or `SCStreamErrorDomain` code `-3801`.

### Supporting Types

```swift
struct PermissionSnapshot {
    let speechAuthorized: Bool
    let microphoneAuthorized: Bool
    let screenCaptureAuthorized: Bool
    var readyDescription: String { /* joins statuses with " • " */ }
}

enum PermissionError: LocalizedError, Equatable {
    case speechRecognition
    case microphone
    case screenRecording
    // Each has descriptive errorDescription pointing to System Settings
}
```

**Imports**: `AppKit`, `AVFAudio`, `Combine`, `CoreGraphics`, `@preconcurrency ScreenCaptureKit`, `Speech`, `SwiftUI`.

---

## Agent 4: Audio Capture (`LiveMeetingCapture`)

**File**: `Coyote/LiveMeetingCapture.swift` (178 lines)

**Responsibility**: Wraps ScreenCaptureKit for dual audio capture (microphone + system audio). Creates and manages the `SCStream` and dispatches sample buffers to the transcription pipeline.

**Inputs**: `start(locale:)` call from ViewModel.

**Outputs**: Callbacks — `onTranscript`, `onLevel`, `onStatus`, `onError`. These are `@MainActor` closures.

### Properties
- `onTranscript: @MainActor (TranscriptUpdate) -> Void`
- `onLevel: @MainActor (CaptionSource, Double) -> Void`
- `onStatus: @MainActor (String) -> Void`
- `onError: @MainActor (Error) -> Void`
- Private: `sampleQueue: DispatchQueue`, `stream: SCStream?`, `pipeline: AudioTranscriptionPipeline?`, `isRunning: Bool`

### `start(locale:) async throws`
1. Guard not already running.
2. Create `AudioTranscriptionPipeline(source: .unified, ...)` with forwarded callbacks.
3. `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`.
   - On `-3801` error: call `CGRequestScreenCaptureAccess()`, sleep 1s, retry once.
4. Find preferred display matching `NSScreen.main?.displayID`.
5. Exclude own app windows by `Bundle.main.bundleIdentifier`.
6. Create `SCContentFilter(display:excludingApplications:exceptingWindows:)`.
7. Configure `SCStreamConfiguration`: `width: 2, height: 2, queueDepth: 3, capturesAudio: true, captureMicrophone: true, excludesCurrentProcessAudio: true, sampleRate: 48000, channelCount: 1`.
8. Create `SCStream`, add outputs for `.audio` and `.microphone`.
9. `try await stream.startCapture()`, set `isRunning = true`.

### `stop() async`
- Stop capture, call `pipeline?.stop()`, nil out stream and pipeline.

### `SCStreamOutput` / `SCStreamDelegate` conformance
- `.microphone` → `pipeline?.append(sampleBuffer:)` (full transcription path)
- `.audio` → `pipeline?.appendLevelOnly(sampleBuffer:)` (level metering only)
- `.screen` → ignored
- `didStopWithError` → forwards to `onError`

### Error Mapping (`CaptureError` enum)
| Code | Case | Description |
|------|------|-------------|
| -3801 | `screenRecordingPermissionOutOfSync` | Stale TCC grant |
| -3803 | `missingScreenCaptureEntitlements` | Missing entitlements |
| -3818 | `failedToStartSystemAudio` | System audio blocked |
| -3820 | `failedToStartMicrophone` | Mic capture blocked |
| n/a | `noAvailableDisplay` | No display found |

**Imports**: `AppKit`, `CoreGraphics`, `Foundation`, `@preconcurrency ScreenCaptureKit`.

---

## Agent 5: Audio Transcription Pipeline (`AudioTranscriptionPipeline`)

**File**: `Coyote/AudioTranscriptionPipeline.swift` (478 lines)

**Responsibility**: Receives raw audio samples, converts to 16kHz mono Float32, accumulates into chunks, encodes as WAV, sends to OpenAI `gpt-4o-transcribe`, filters hallucinations, and emits transcription results.

**Inputs**: `CMSampleBuffer` via `append(sampleBuffer:)` and `appendLevelOnly(sampleBuffer:)`.

**Outputs**: Callbacks — `onTranscript: @MainActor (TranscriptUpdate) -> Void`, `onLevel: @MainActor (CaptionSource, Double) -> Void`, `onStatus`, `onError`.

### Configuration Constants
| Constant | Value |
|----------|-------|
| `transcriptionModel` | `"gpt-4o-transcribe"` |
| `chunkDuration` | `8.0` seconds |
| `overlapDuration` | `1.0` seconds |
| `sampleRate` (target) | `16000` Hz |
| `silenceTimeout` | `2.0` seconds |
| HTTP timeout | `30` seconds |

### State Machine
```swift
private enum State { case idle, preparing, ready, failed }
```

### Core State
- `pcmAccumulator: [Float]`, `overlapBuffer: [Float]`, `accumulatedFrames: UInt32`
- `converter: AVAudioConverter?`, `targetFormat: AVAudioFormat?`, `sourceFormat: AVAudioFormat?`
- `isTranscribing: Bool`, `silenceTimer: DispatchWorkItem?`, `lastPartialText: String`
- Processing on `DispatchQueue(label: "Coyote.pipeline.\(source.rawValue)")`

### `append(sampleBuffer:)` flow
1. `.idle` → `.preparing` → `configure(using:)`: extract natural format, create 16kHz mono Float32 target format, create `AVAudioConverter` if formats differ.
2. `.ready` → `processReady(_:)`:
   a. Convert to PCM → convert to target format.
   b. Accumulate Float32 samples in `pcmAccumulator`.
   c. Reset silence timer (2s `DispatchWorkItem`).
   d. If accumulated duration ≥ `chunkDuration` → `flushChunk()`.
   e. Emit partial "Listening..." update if > 0.5s accumulated and not transcribing.
   f. Emit level via `onLevel`.

### `flushChunk()`
1. Prepend `overlapBuffer` to `pcmAccumulator`.
2. Save tail (`overlapDuration * sampleRate` frames) as new `overlapBuffer`.
3. Clear accumulator, set `isTranscribing = true`.
4. Encode to WAV → `transcribeAudio(wavData:)`.
5. Apply hallucination filter.
6. Emit final transcript via `onTranscript`.

### WAV Encoding (`encodeWAV(samples:sampleRate:) -> Data`)
- 44-byte RIFF/WAVE header: PCM format, 1 channel, 16-bit.
- Float samples clamped to [-1,1] × 32767 → Int16 little-endian.

### `transcribeAudio(wavData:) async -> String?`
- **Endpoint**: `POST https://api.openai.com/v1/audio/transcriptions`
- **Auth**: `Bearer \(Env.openAIKey)`
- **Content-Type**: `multipart/form-data`
- **Fields**: `model=gpt-4o-transcribe`, `language=en`, `response_format=text`
- **File**: `audio.wav`, content-type `audio/wav`

### Hallucination Filter
- Exact match (case-insensitive): "thank you", "thanks for watching", "please subscribe", "you", "bye"
- Starts with: "this is a business meeting", "accurately transcribe"

### Audio Conversion (`convertIfNeeded`)
- Uses `AVAudioConverter` with input-block pattern.
- Handles format changes by recreating converter.

### `stop()`
- Cancels silence timer, flushes remaining audio, clears all state, resets to `.idle`.

### Supporting Types
```swift
enum CaptionSource: String, Sendable {
    case microphone, systemAudio, unified
    var displayName: String { ... }
}

struct TranscriptUpdate: Sendable {
    let source: CaptionSource
    let text: String
    let isFinal: Bool
}

enum PipelineError: LocalizedError {
    case unsupportedLocale(String)
    case converterUnavailable
    case outputBufferCreation
    case emptyConversion(Int)
}
```

### Logging
- `CoyoteDiag.log` in home directory. Format: `\(Date()) \(msg)`.

**Imports**: `@preconcurrency AVFoundation`, `CoreMedia`, `Foundation`.

---

## Agent 6: Audio Utilities

**File**: `Coyote/AudioUtilities.swift` (118 lines)

**Responsibility**: Extensions for converting audio buffers and extracting display IDs.

### `CMSampleBuffer.makePCMBuffer() throws -> AVAudioPCMBuffer`
1. Extract `CMFormatDescription` → `AudioStreamBasicDescription` → `AVAudioFormat`.
2. Allocate `AVAudioPCMBuffer` with `frameCapacity = CMSampleBufferGetNumSamples`.
3. `CMSampleBufferCopyPCMDataIntoAudioBufferList`.
4. Set `frameLength`.

### `AVAudioPCMBuffer.normalizedPowerLevel() -> Double`
- Handles `.pcmFormatFloat32`, `.pcmFormatInt16`, `.pcmFormatInt32`.
- Calculates average absolute amplitude across all channels.
- Scales by 2.8×, clamps to [0.02, 1.0].

### `NSScreen.displayID: CGDirectDisplayID?`
- Extracts from `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`.

### Error Enum
```swift
enum AudioBufferConversionError: LocalizedError {
    case missingFormatDescription
    case missingStreamDescription
    case unsupportedAudioFormat
    case pcmBufferAllocation
    case copyFailed(OSStatus)
}
```

**Imports**: `AppKit`, `AVFoundation`, `CoreMedia`.

---

## Agent 7: Entity Extractor (`EntityExtractor`)

**File**: `Coyote/EntityExtractor.swift` (212 lines)

**Responsibility**: Uses Claude API to extract person and company entities from transcribed text, with context window and cooldown deduplication.

**Inputs**: Finalized caption text via `extract(from:completion:)`.

**Outputs**: Array of `ExtractedEntity` via completion callback.

### Configuration
| Parameter | Value |
|-----------|-------|
| Model | `claude-sonnet-4-20250514` |
| Max tokens | 256 |
| HTTP timeout | 10 seconds |
| Cooldown | 15 seconds per entity |
| Context window | Last 5 captions |

### Data Models
```swift
enum EntityKind: String, Sendable, Hashable, Codable { case person, company }

struct ExtractedEntity: Sendable, Hashable {
    let kind: EntityKind
    let name: String
    let associatedCompany: String?
    let timestamp: Date
}
```

### Class: `final class EntityExtractor: @unchecked Sendable`
- `queue: DispatchQueue` — serializes state access.
- `recentEntities: [String: Date]` — cooldown tracking, keyed by `"{kind}:{lowercased_name}"`.
- `recentCaptions: [String]` — rolling buffer, max 5.
- `claudeAPIKey: String` — defaults to `Env.claudeAPIKey`.

### `extract(from text:, completion:)`
1. Trim text, guard ≥ 3 chars.
2. Sync on queue: build context from `recentCaptions`, append trimmed text (cap at 5).
3. `Task { await callClaude(...) }` → pass results to completion.

### `callClaude(text:, context:) async -> [ExtractedEntity]`
1. Build system prompt (fully generic, no hardcoded names — see Skill.md for full text).
2. User message: if context empty: `"Extract entities from this meeting transcript segment:\n\"{text}\""`. If context present: `"Recent context: {context}\n\nExtract entities from this NEW segment (use context for associations):\n\"{text}\""`.
3. POST to `https://api.anthropic.com/v1/messages` with headers: `Content-Type: application/json`, `anthropic-version: 2023-06-01`, `x-api-key: {claudeAPIKey}`.
4. Parse response: `json["content"][0]["text"]`.
5. Strip markdown code fences if present.
6. Parse JSON: `{"entities": [...]}`.
7. For each entity: check cooldown (15s), dedup within batch, apply cooldown, build `ExtractedEntity`.
8. `pruneOldEntities` — remove entries older than 45s (3× cooldown).

### `clearCooldown(for lowerName:)`
- Removes all keys ending with `":{lowerName}"` from `recentEntities`.

### `reset()`
- Clears `recentEntities` and `recentCaptions`.

### Logging
- `~/Coyote-Entity.log`. Format: `\(Date()) [Entity] \(msg)`.

**Imports**: `Foundation`.

---

## Agent 8: Crustdata Client (`CrustdataClient`)

**File**: `Coyote/CrustdataClient.swift` (1040 lines)

**Responsibility**: Actor-based API client for Crustdata's company/person search, enrichment, full enrichment, and web search endpoints. Includes caching, throttling, and response mapping.

**Inputs**: Method calls from `IntelligenceEngine`.

**Outputs**: `CrustdataPersonResult`, `CrustdataCompanyResult`, `[CrustdataWebResult]`.

### Configuration
| Parameter | Value |
|-----------|-------|
| Base URL | `https://api.crustdata.com` |
| API version | `2025-11-01` (header `x-api-version`) |
| Auth | `authorization: Bearer {apiKey}` |
| Request timeout | 15 seconds |
| Resource timeout | 30 seconds |
| Max concurrent | 4 |
| Rate limit retry | Up to 2 retries on HTTP 429, backoff `(retryCount+1) * 5s` |

### Class: `actor CrustdataClient`

### Public Methods

#### Company
- **`searchCompany(name:) -> [CrustdataCompanyResult]`** — POST `/company/search`, filter `basic_info.name`, limit 3.
- **`enrichCompany(name:) -> CrustdataCompanyResult?`** — First tries `/company/search` (limit 1, returns full data). Fallback: POST `/company/enrich` with `{"names": [name]}`, picks highest-confidence match.
- **`fullEnrichCompany(domain:, name:) -> CrustdataCompanyResult?`** — POST `/company/enrich` with `{"domains": [domain]}` or `{"names": [name]}`. Extracts `taxonomy.professionalNetworkSpecialities` into `specialities`.

#### Person
- **`searchPerson(name:, companyName:) -> [CrustdataPersonResult]`** — POST `/person/search`. With company: AND filter on `basic_profile.name` + `experience.employment_details.company_name`. Without: single name filter. Limit 3.
- **`enrichPerson(firstName:, lastName:, companyName:) -> CrustdataPersonResult?`** — Uses `/person/search` with limit 1 (since `/person/enrich` requires LinkedIn URL).
- **`fullEnrichPerson(linkedinUrl:) -> CrustdataPersonResult?`** — POST `/person/enrich` with `{"linkedin_profile_url": url}`. Returns enriched person with education, skills, social handles, past employment.

#### Web
- **`webSearch(query:) -> [CrustdataWebResult]`** — POST `/web/search/live` with `{"query": query}`.

#### Cache
- **`clearCache()`** — removes all entries.

### Internal Networking
- `postRequest<T: Decodable>(endpoint:, body:, retryCount:) -> T?` — generic POST with JSON body, snake_case decoding, retry on 429, throttle/unthrottle on every path.

### Mapping Functions
- `mapPersonResult(_ profile:)` — extracts name, title, location, LinkedIn URL, current employer from `PersonProfile`.
- `mapFullEnrichPerson(_ data:)` — full mapping including education, past employment, business emails, skills, Twitter, GitHub, LinkedIn followers.
- `mapCompanySearchResult(_ company:)` — maps full company search data including headcount, funding, revenue, location.
- Helpers: `formatLargeNumber`, `formatRevenueRange`, `parseYear`.

### Public Result Models

See Skill.md for complete struct definitions. Key models:
- `CrustdataPersonResult` — 17 fields including full-enrich fields (summary, headline, profilePictureUrl, twitterHandle, githubUrl, businessEmails, education, skills, pastEmployment, languages, linkedinFollowers).
- `CrustdataCompanyResult` — 19 fields including full-enrich fields (allDomains, specialities, investors).
- `PersonEducationEntry`, `PersonEmploymentEntry` — sub-models.
- `CrustdataWebResult` — Decodable web search result.

### Private Decodable Models (28 structs)
Person: `PersonSearchResponse`, `PersonProfile`, `PersonBasicProfile`, `PersonLocation`, `PersonExperience`, `EmploymentDetails`, `EmploymentRecord`, `PersonEducation`, `SchoolRecord`, `PersonContact`, `BusinessEmail`, `PersonSocialHandles`, `ProfessionalNetworkId`, `TwitterId`.

Person Full Enrich: `PersonFullEnrichResult`, `PersonFullEnrichMatch`, `PersonFullEnrichData`, `PersonFullExperience`, `FullEmploymentDetails`, `FullEnrichEmploymentRecord`, `FullEnrichLocation`, `PersonSkills`, `ProfessionalNetworkProfile`, `DevPlatformProfile`.

Company: `CompanySearchResponse`, `CompanySearchRecord`, `CompanyEnrichResult`, `CompanyEnrichMatch`, `CompanyEnrichData`, `CompanyBasicInfo`, `CompanyHeadcount`, `CompanyFunding`, `CompanyLocations`, `CompanyTaxonomy`, `CompanyRevenue`, `RevenueEstimated`.

Web: `WebSearchResponse`.

### Logging
- `~/Coyote-Crustdata.log`. Format: `\(Date()) [Crustdata] \(msg)`.

**Imports**: `Foundation`.

---

## Agent 9: Intelligence Engine (`IntelligenceEngine`)

**File**: `Coyote/IntelligenceEngine.swift` (684 lines)

**Responsibility**: The orchestration layer. Receives finalized captions, triggers entity extraction via Claude, enriches entities via Crustdata, manages insights/chips/news, and supports full enrichment.

**Inputs**: `processFinalizedCaption(_:)` from ViewModel, `fullEnrich(insightId:)` from UI, `editEntity`/`removeEntity` from user actions.

**Outputs**: Published state consumed by ContentView: `insights`, `entityChips`, `newsItems`, `enrichingEntityNames`.

### Class: `@MainActor final class IntelligenceEngine: ObservableObject`

### Published State
- `insights: [IntelligenceInsight]` — max 8
- `entityChips: [CaptionEntry]` — max 10
- `newsItems: [CompanyNewsItem]` — max 12
- `enrichingEntityNames: Set<String>` — entity names currently being full-enriched

### Private State
- `crustdata: CrustdataClient`
- `extractor: EntityExtractor`
- `pendingKeys: Set<String>` — `"{kind}:{lowercased_name}"`
- `lookupQueue: [ExtractedEntity]`
- `lookupTask: Task<Void, Never>?`
- `newsSearchedCompanies: Set<String>`
- `enrichedEntityNames: Set<String>` — entities already full-enriched (by lowercased name)

### Data Models (defined in this file)
```swift
struct IntelChip: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

struct IntelligenceInsight: Identifiable, Sendable {
    let id = UUID()
    let entityName: String
    let sourceEntityName: String
    let kind: EntityKind
    let chips: [IntelChip]
    let timestamp: Date
}

struct CompanyNewsItem: Identifiable, Sendable {
    let id = UUID()
    let companyName: String
    let headline: String
    let summary: String
    let icon: String
    let timestamp: Date
}
```

### Core Flow
1. `processFinalizedCaption(_:)` → `extractor.extract(from:)` → `handleEntities(_:)`.
2. `handleEntities(_:)` — for each entity: skip if pending/has insight, add chip immediately, add to queue, call `processQueue()`.
3. `processQueue()` — guard single `lookupTask`, drain queue, run all lookups in parallel via `withTaskGroup`, remove from `pendingKeys` on completion, recurse if more queued.
4. `lookup(_:)` → routes to `lookupCompany` or `lookupPerson`.

### Company Lookup (`lookupCompany`)
1. `crustdata.searchCompany(name:)` → if found, guard chip still exists, `addInsight(from:entityName:)`.
2. Fallback: `crustdata.enrichCompany(name:)`.
3. If both fail: keep chip, trigger news fetch anyway.

### Person Lookup (`lookupPerson`)
1. `crustdata.searchPerson(name:, companyName:)` with company filter.
2. If empty + had company filter: retry without company.
3. `pickBestPersonResult` — prefers result matching associated company.
4. Fallback: split name, `crustdata.enrichPerson(firstName:, lastName:, companyName: nil)`.

### `pickBestPersonResult` Heuristic
- Prefer result whose company name/title contains associated company.
- Trust API-filtered results even if heuristic doesn't match.
- Return `nil` if no match (don't show wrong person).

### Insight Building
- `addInsight(from company:, entityName:)` — builds chips, inserts insight, triggers news.
- `addInsight(from person:, entityName:)` — builds person chips + company chips, uses longer of entityName/fullName as display name.
- `insertInsight(_:)` — upserts by `entityName.lowercased()`, caps at 8.

### Chip Builders

**`buildPersonChips`** — maps person fields to `IntelChip` with SF Symbols:
| Field | Label | Icon |
|-------|-------|------|
| title | Title | person.text.rectangle |
| headline (if ≠ title) | Headline | text.quote |
| email + extra business emails | Email | envelope |
| linkedinUrl | LinkedIn | link |
| location | Location | mappin.and.ellipse |
| twitterHandle | Twitter | at |
| githubUrl | GitHub | chevron.left.forwardslash.chevron.right |
| linkedinFollowers | Followers | person.2 |
| summary (max 200 chars) | About | doc.text |
| education (max 3) | Education | graduationcap |
| skills (max 10, joined) | Skills | star |
| pastEmployment (max 3) | Past Role | clock.arrow.circlepath |
| languages (joined) | Languages | globe |

**`buildCompanyChips`** — maps company fields:
| Field | Label | Icon |
|-------|-------|------|
| industry | Industry | building.2 |
| employeeRange/employeeCount | Headcount | person.3 |
| revenueRangePrinted | Revenue | dollarsign.circle |
| totalFunding (+ stage) | Funding | banknote |
| founded | Founded | calendar |
| type | Type | tag |
| location | HQ | mappin.and.ellipse |
| website | Web | globe |
| descriptionAi (max 120) | About | doc.text |
| investors (max 5, joined) | Investors | dollarsign.arrow.circlepath |
| specialities (max 8, joined) | Specialities | list.bullet |

### Full Enrich
- `fullEnrich(insightId:)` — guards not already enriched, adds to `enrichingEntityNames`, dispatches async.
- `fullEnrichPerson(insight:)` — extracts LinkedIn URL from chips, calls `crustdata.fullEnrichPerson`, merges chips.
- `fullEnrichCompany(insight:)` — extracts domain from "Web" chip, calls `crustdata.fullEnrichCompany`, merges chips.
- `mergeChips(existing:, enriched:)` — multi-value labels (`Email`, `Education`, `Past Role`) allow duplicates by label but deduplicate on `label|value.lowercased()` pairs. Single-value labels: update if enriched value is longer.
- `isEnriching(entityName:)`, `isEnriched(entityName:)` — check by lowercased name.

### Entity Management
- `removeEntity(named:)` — removes chip, insight, pending keys, queue items, news items, news search tracking, extractor cooldown, enrichment tracking.
- `editEntity(oldName:, newName:)` — preserves old kind if known, removes old, adds new chip, re-queues lookup.
- `reset()` — cancels task, clears everything.

### Live News (`fetchCompanyNews`, nonisolated async)
- `crustdata.webSearch(query: "{companyName} latest news")` → take first 5.
- Map to `CompanyNewsItem` with icon "globe".
- Before inserting on MainActor: guard chip or insight still exists (race condition protection).
- Insert at front, cap at 12.

### Logging
- `~/Coyote-Intel.log`. Format: `\(Date()) [Intel] \(msg)`.

**Imports**: `Foundation`, `SwiftUI`.

---

## Agent 10: UI Layer (`ContentView`)

**File**: `Coyote/ContentView.swift` (688 lines)

**Responsibility**: The complete SwiftUI UI — header, caption panel, intelligence card, news card, and all sub-components.

**Inputs**: `CaptionBarViewModel` as `EnvironmentObject`.

**Outputs**: Visual rendering of the app state.

### Design System
- **Colors**: Pure monochrome. Black background, white text at various opacities. NO colored accents (except green checkmark for enriched).
- **Font**: System serif (`.design(.serif)`) everywhere.
- **Cards**: `RoundedRectangle` with white 4-5% fill + 8-15% stroke.

### Overall Layout
- ZStack: `RoundedRectangle(cornerRadius: 32)` black fill + 15% white stroke + shadow.
- VStack(spacing: 12): header, captionPanel, GeometryReader with HStack (2/3 intelligence, 1/3 news).
- Frame: minWidth 860, idealWidth 980, maxWidth 1080, minHeight 600, maxHeight 780.

### Components (all `private struct` or `private var`)
1. **`header`** — status dot (animated pulse when running), status/detail text, Start/Stop/Reset buttons, Integrations menu.
2. **`captionPanel`** — Label with audio icon, `AudioLevelView`, `TypewriterCaptionView`, horizontal `ScrollView` of `EditableCaptionChip`.
3. **`intelligenceCard`** — sparkles header + count, empty state, `ScrollView` of `InsightRow`.
4. **`companyNewsCard`** — newspaper header + count, empty state, `ScrollView` of `NewsItemRow`.
5. **`NewsItemRow`** — company badge, headline (2 lines), summary (3 lines).
6. **`InsightRow`** — expandable: entity icon + name + field count + chevron. Expanded: chips + "Full Enrich" button with progress indicator. Tracks `isEnriching`/`isEnriched` by entity name.
7. **`IntelChipRowView`** — icon + label (62pt width) + value + copy/open action. Detects URLs, Email, LinkedIn, Web as openable.
8. **`EditableCaptionChip`** — normal display, hover shows X, double-tap to edit (inline TextField), Enter commits, Escape cancels.
9. **`TypewriterCaptionView`** — text or placeholder, blinking caret capsule.
10. **`AudioLevelView`** — `TimelineView(.animation(minimumInterval: 1/24))`, 12 capsule bars with wave animation.
11. **`AnimatedBackdrop`** — `Color.black` (minimal).
12. **`PillButtonStyle`** — capsule fill, 13pt semibold serif, press scale 0.97 + opacity 0.78.
13. **`WindowAccessor`** — `NSViewRepresentable` that extracts `NSWindow` in `makeNSView`/`updateNSView`.

**Imports**: `SwiftUI`.

---

## Agent 11: Configuration & Metadata Files

### `Coyote/Info.plist` (37 lines)
- `CFBundleDisplayName`: Coyote
- `LSApplicationCategoryType`: public.app-category.productivity
- `LSUIElement`: false
- `NSAudioCaptureUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` — all present.

### `Coyote/Coyote.entitlements` (9 lines)
- `com.apple.security.device.audio-input`: true

### `.gitignore` (8 lines)
```
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.log
.env
```

### `.env` (not committed, gitignored)
```
OPENAI_API_KEY=<YOUR_OPENAI_KEY>
CLAUDE_API_KEY=<YOUR_CLAUDE_KEY>
CRUSTDATA_API_TOKEN=<YOUR_CRUSTDATA_TOKEN>
```

### Asset Catalog (`Coyote/Assets.xcassets/`)
- `AppIcon.appiconset/` — app icon
- Integration icons (SVG, template rendering): `slack.imageset/slack.svg`, `discord.imageset/discord.svg`, `teams.imageset/teams.svg`, `salesforce.imageset/salesforce.svg`, `hubspot.imageset/hubspot.svg`

### Xcode Project Settings
- **Product Name**: Coyote
- **Bundle Identifier**: `com.coyote.app`
- **Deployment Target**: macOS 26.0
- **Swift Version**: 5.0
- **Marketing Version**: 1.0

---

## Log Files Reference

| File | Writer | Tag | Content |
|------|--------|-----|---------|
| `~/CoyoteDiag.log` | AudioTranscriptionPipeline | (date only) | Format config, chunk timing, STT results |
| `~/Coyote-Entity.log` | EntityExtractor | `[Entity]` | Claude requests/responses, cooldown |
| `~/Coyote-Intel.log` | IntelligenceEngine | `[Intel]` | Crustdata lookups, news fetches, insights |
| `~/Coyote-Captions.log` | CaptionBarViewModel | `[ISO8601] [FINAL/PARTIAL]` | All captions |
| `~/Coyote-Crustdata.log` | CrustdataClient | `[Crustdata]` | Raw API requests/responses |
