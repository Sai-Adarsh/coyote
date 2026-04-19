# Plan.md — Step-by-Step Build Plan for Coyote

This document provides a **precise, ordered plan** for a coding agent to recreate the entire Coyote project from scratch. Follow each step sequentially. Every file, configuration, and line of code is covered in the companion documents (`Skill.md` through `Skill-5.md` for exact code, `Agents.md` for behavioral specifications).

---

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** with Swift 5.0
- **API Keys** (obtain before starting):
  - `OPENAI_API_KEY` — from [platform.openai.com](https://platform.openai.com)
  - `CLAUDE_API_KEY` — from [console.anthropic.com](https://console.anthropic.com)
  - `CRUSTDATA_API_TOKEN` — from [crustdata.com](https://crustdata.com)

---

## Phase 1: Project Scaffolding

### Step 1.1: Create Xcode Project
1. Open Xcode → File → New → Project.
2. Select **macOS → App**.
3. Configure:
   - **Product Name**: `Coyote`
   - **Team**: Your development team
   - **Organization Identifier**: `com.coyote`
   - **Bundle Identifier**: `com.coyote.app`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
   - Uncheck "Include Tests"
4. Save to your desired directory.

### Step 1.2: Configure Build Settings
In the Xcode project settings:
- **Deployment Target**: macOS 14.0
- **Swift Language Version**: Swift 5
- **Marketing Version**: 1.0
- **Current Project Version**: 1

### Step 1.3: Create `.gitignore`
Create `.gitignore` at the project root with exact content from **SKILL.md § .gitignore**.

### Step 1.4: Create `.env`
Create `.env` at the project root (this file is gitignored):
```
OPENAI_API_KEY=<YOUR_OPENAI_KEY>
CLAUDE_API_KEY=<YOUR_CLAUDE_KEY>
CRUSTDATA_API_TOKEN=<YOUR_CRUSTDATA_TOKEN>
```

### Step 1.5: Create `README.md`
Create `README.md` at the project root with exact content from **SKILL.md § README.md**.

### Step 1.6: Initialize Git
```bash
cd coyote
git init
git add .
git commit -m "Initial project scaffolding"
```

---

## Phase 2: App Configuration Files

### Step 2.1: Replace `Info.plist`
Replace the auto-generated `Coyote/Info.plist` with the exact content from **SKILL.md § Info.plist**. Key additions:
- `NSAudioCaptureUsageDescription` — system audio capture permission string
- `NSMicrophoneUsageDescription` — microphone permission string
- `NSSpeechRecognitionUsageDescription` — speech recognition permission string
- `LSApplicationCategoryType` — `public.app-category.productivity`

### Step 2.2: Create `Coyote.entitlements`
Create `Coyote/Coyote.entitlements` with exact content from **SKILL.md § Coyote.entitlements**.
- Grants `com.apple.security.device.audio-input` entitlement.
- In Xcode, go to project → Signing & Capabilities → add "Audio Input" if not auto-detected.

### Step 2.3: Set Up Asset Catalog
1. The default `Assets.xcassets` should already exist.
2. Create icon imagesets for integrations: `slack`, `discord`, `teams`, `salesforce`, `hubspot`.
3. For each, create a folder `<name>.imageset/` containing:
   - The SVG logo file (`<name>.svg`) — source from official brand asset pages
   - `Contents.json` with `template-rendering-intent: template` and `preserves-vector-representation: true` (see **SKILL.md § Asset Catalog**)
4. Configure `AppIcon.appiconset` with standard macOS icon sizes (see **SKILL.md § AppIcon**).

### Step 2.4: Commit
```bash
git add -A
git commit -m "Add Info.plist, entitlements, and asset catalog"
```

---

## Phase 3: Foundation Layer

> Build order matters. Each file may depend on previously created files.

### Step 3.1: `EnvLoader.swift`
Create `Coyote/EnvLoader.swift` with exact code from **SKILL.md § EnvLoader.swift**.
- Defines the `Env` enum with static properties for API keys.
- Must be created before any file that references `Env.openAIKey`, `Env.claudeAPIKey`, or `Env.crustdataToken`.

### Step 3.2: `AudioUtilities.swift`
Create `Coyote/AudioUtilities.swift` with exact code from **SKILL.md § AudioUtilities.swift**.
- Defines `AudioBufferConversionError`, `CMSampleBuffer.makePCMBuffer()`, `AVAudioPCMBuffer.normalizedPowerLevel()`, `NSScreen.displayID`.
- Required by `AudioTranscriptionPipeline` and `LiveMeetingCapture`.

### Step 3.3: Build & Verify
Build the project (⌘B). Should compile with no errors. These are standalone utility files.

### Step 3.4: Commit
```bash
git add -A
git commit -m "Add EnvLoader and AudioUtilities"
```

---

## Phase 4: Audio Pipeline

### Step 4.1: `AudioTranscriptionPipeline.swift`
Create `Coyote/AudioTranscriptionPipeline.swift` with exact code from **SKILL.md § AudioTranscriptionPipeline.swift**.
- Defines `CaptionSource`, `TranscriptUpdate`, `AudioTranscriptionPipeline`, `PipelineError`.
- 478 lines. Handles audio chunking, WAV encoding, OpenAI gpt-4o-transcribe API calls, hallucination filtering.
- Depends on: `Env` (for OpenAI key), `AudioUtilities` (for `makePCMBuffer`, `normalizedPowerLevel`).

### Step 4.2: `LiveMeetingCapture.swift`
Create `Coyote/LiveMeetingCapture.swift` with exact code from **SKILL.md § LiveMeetingCapture.swift**.
- Defines `LiveMeetingCapture`, `CaptureError`.
- Uses ScreenCaptureKit to capture microphone + system audio.
- Depends on: `AudioTranscriptionPipeline`, `AudioUtilities` (for `NSScreen.displayID`).

### Step 4.3: Build & Verify
Build (⌘B). Should compile. The `PermissionError` type referenced in `LiveMeetingCapture` is defined later in `CaptionBarViewModel.swift` — if the compiler complains, proceed to Phase 5 first, or temporarily comment out the reference.

### Step 4.4: Commit
```bash
git add -A
git commit -m "Add audio transcription pipeline and live meeting capture"
```

---

## Phase 5: Intelligence Layer

### Step 5.1: `EntityExtractor.swift`
Create `Coyote/EntityExtractor.swift` with exact code from **SKILL.md § EntityExtractor.swift**.
- Defines `EntityKind`, `ExtractedEntity`, `EntityExtractor`.
- Uses Claude API (claude-sonnet-4-20250514) for entity extraction.
- Depends on: `Env` (for Claude API key).

### Step 5.2: `CrustdataClient.swift`
Create `Coyote/CrustdataClient.swift` with exact code from **SKILL.md § CrustdataClient.swift**.

This is the largest file (1040 lines). It must be a single file containing:
1. The `crustLog` function
2. The `CrustdataClient` actor with all methods
3. Public result models: `CrustdataPersonResult`, `PersonEducationEntry`, `PersonEmploymentEntry`, `CrustdataCompanyResult`, `CrustdataWebResult`
4. Private API response models: all `Decodable` structs for person search, company search, company enrich, person full enrich, and web search responses

### Step 5.3: `IntelligenceEngine.swift`
Create `Coyote/IntelligenceEngine.swift` with exact code from **SKILL.md § IntelligenceEngine.swift**.
- Defines `IntelChip`, `IntelligenceInsight`, `CompanyNewsItem`, `IntelligenceEngine`.
- 684 lines. The orchestration layer: entity extraction → Crustdata lookup → insight building → news fetching → full enrich.
- Depends on: `EntityExtractor`, `CrustdataClient`, `CaptionEntry` (from CaptionBarViewModel).

**Note**: `CaptionEntry` is defined in `CaptionBarViewModel.swift`. If building incrementally, create that file first or temporarily define `CaptionEntry` here.

### Step 5.4: Build & Verify
Build (⌘B). May need `CaptionBarViewModel.swift` for `CaptionEntry`. If so, proceed to Phase 6 first.

### Step 5.5: Commit
```bash
git add -A
git commit -m "Add entity extractor, Crustdata client, and intelligence engine"
```

---

## Phase 6: ViewModel & UI

### Step 6.1: `CaptionBarViewModel.swift`
Create `Coyote/CaptionBarViewModel.swift` with exact code from **SKILL.md § CaptionBarViewModel.swift**.
- Defines `CaptionEntry`, `TranscriptPanelState`, `CaptionBarViewModel`, `PermissionSnapshot`, `PermissionError`.
- 368 lines. Central ViewModel: owns capture lifecycle, permissions, window configuration, and routes transcripts.
- Depends on: `LiveMeetingCapture`, `IntelligenceEngine`, `Env`.

### Step 6.2: `ContentView.swift`
Create `Coyote/ContentView.swift` with exact code from **SKILL.md § ContentView.swift**.
- Defines `ContentView` and all private sub-views: `NewsItemRow`, `InsightRow`, `IntelChipRowView`, `EditableCaptionChip`, `TypewriterCaptionView`, `AudioLevelView`, `AnimatedBackdrop`, `PillButtonStyle`, `WindowAccessor`.
- 688 lines. Pure SwiftUI, no external UI dependencies.
- Depends on: `CaptionBarViewModel`, `IntelligenceEngine` types.

### Step 6.3: `CoyoteApp.swift`
Replace the auto-generated `CoyoteApp.swift` with exact code from **SKILL.md § CoyoteApp.swift**.
- 29 lines. Sets up the app entry point with `AppDelegate`.

### Step 6.4: Build & Verify
Build (⌘B). **This should compile with zero errors.** All types are now defined:
- `CaptionEntry` in CaptionBarViewModel
- `PermissionError` in CaptionBarViewModel
- `IntelChip`, `IntelligenceInsight`, `CompanyNewsItem` in IntelligenceEngine
- All Crustdata models in CrustdataClient

### Step 6.5: Commit
```bash
git add -A
git commit -m "Add ViewModel, ContentView, and app entry point"
```

---

## Phase 7: Testing & Verification

### Step 7.1: Run the App
1. Build and Run (⌘R).
2. The app should launch as a floating overlay window, dark theme, positioned at the bottom center of the screen.
3. You should see: header with status/Start button, caption panel with placeholder text, Intelligence and Live News cards (both empty).

### Step 7.2: Grant Permissions
1. Click **Start**.
2. Grant permissions when prompted:
   - Microphone access
   - Speech Recognition access
   - Screen & System Audio Recording (in System Settings)
3. After granting, the app should show "Live captions running".

### Step 7.3: Verify Transcription
1. Play audio or speak into the microphone.
2. Live captions should appear in the caption panel with a typewriter effect.
3. The audio level visualizer should animate in response to audio.

### Step 7.4: Verify Entity Extraction
1. Mention a person or company name (e.g., "Elon Musk" or "Tesla").
2. Entity chips should appear below the caption panel.
3. Intelligence insights should populate with enriched data from Crustdata.

### Step 7.5: Verify Full Enrich
1. Expand an insight row by clicking it.
2. Click "Full Enrich" button.
3. Additional fields (education, skills, past roles, etc.) should appear after enrichment completes.
4. A green checkmark seal should appear on the enriched insight.

### Step 7.6: Verify Live News
1. When a company is mentioned, the Live News card should populate with recent headlines.
2. News items show company name, headline, and summary.

### Step 7.7: Verify Entity Management
1. **Remove**: Hover over an entity chip, click the X button. Chip, insight, and associated news should be removed.
2. **Edit**: Double-click an entity chip, type a new name, press Enter. Old data removed, new lookup triggered.
3. **Reset**: Click the Reset button. All captions, chips, insights, and news should clear.

### Step 7.8: Verify Logging
Check `~/` for log files:
- `CoyoteDiag.log` — pipeline diagnostics
- `Coyote-Captions.log` — all transcriptions with timestamps
- `Coyote-Entity.log` — Claude extraction results
- `Coyote-Intel.log` — intelligence engine operations
- `Coyote-Crustdata.log` — all Crustdata API calls and responses

---

## Phase 8: Final Polish

### Step 8.1: Verify Window Behavior
- Window should be always-on-top (floating level).
- Draggable by background.
- Joins all spaces.
- Resizable between min 860×600 and max 1080×780.

### Step 8.2: Verify Integrations Menu
- Click the "Integrations" dropdown.
- Should show Slack, Discord, Teams (separated by divider), Salesforce, HubSpot.
- These are placeholder buttons — no functionality yet.

### Step 8.3: Final Commit
```bash
git add -A
git commit -m "Coyote v1.0 — complete build"
```

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                        CoyoteApp                            │
│  (@main, WindowGroup, AppDelegate)                          │
├─────────────────────────────────────────────────────────────┤
│                       ContentView                           │
│  (SwiftUI: header, captions, intelligence, news)            │
├─────────────────────────────────────────────────────────────┤
│                  CaptionBarViewModel                        │
│  (Permissions, capture lifecycle, UI state)                  │
├──────────────────────┬──────────────────────────────────────┤
│   LiveMeetingCapture │       IntelligenceEngine             │
│   (ScreenCaptureKit) │  (Orchestration: extract→enrich)     │
├──────────────────────┤──────────────┬───────────────────────┤
│ AudioTranscription   │ EntityExtractor  │  CrustdataClient  │
│ Pipeline             │ (Claude API)     │  (Crustdata APIs)  │
│ (OpenAI gpt-4o-      │                  │  - /company/search │
│  transcribe)         │                  │  - /company/enrich │
├──────────────────────┤                  │  - /person/search  │
│  AudioUtilities      │                  │  - /person/enrich  │
│  (CMSampleBuffer     │                  │  - /web/search/live│
│   extensions)        │                  │                    │
├──────────────────────┴──────────────┴───────────────────────┤
│                       EnvLoader                             │
│  (API keys from .env file)                                  │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

```
Mic/System Audio
    → ScreenCaptureKit (LiveMeetingCapture)
    → AudioTranscriptionPipeline (8s chunks → OpenAI gpt-4o-transcribe)
    → TranscriptUpdate (final text)
    → CaptionBarViewModel.applyTranscript()
    → IntelligenceEngine.processFinalizedCaption()
    → EntityExtractor.extract() (Claude claude-sonnet-4-20250514)
    → [ExtractedEntity] (person/company)
    → IntelligenceEngine.handleEntities()
    → CrustdataClient.searchCompany/searchPerson/enrichCompany/enrichPerson
    → addInsight() → buildChips() → insertInsight()
    → fetchCompanyNews() (for companies)
    → UI updates via @Published properties
```

## API Endpoints Used

| Service | Endpoint | Purpose |
|---------|----------|---------|
| OpenAI | `POST /v1/audio/transcriptions` | Speech-to-text (gpt-4o-transcribe) |
| Anthropic | `POST /v1/messages` | Entity extraction (claude-sonnet-4-20250514) |
| Crustdata | `POST /company/search` | Company lookup by name |
| Crustdata | `POST /company/enrich` | Company enrichment by name/domain |
| Crustdata | `POST /person/search` | Person lookup by name |
| Crustdata | `POST /person/enrich` | Person full enrichment by LinkedIn URL |
| Crustdata | `POST /web/search/live` | Live web/news search |

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| Max insights | 8 | IntelligenceEngine |
| Max entity chips | 10 | IntelligenceEngine |
| Max news items | 12 | IntelligenceEngine |
| Audio chunk duration | 8s | AudioTranscriptionPipeline |
| Audio overlap duration | 1s | AudioTranscriptionPipeline |
| Silence timeout | 2s | AudioTranscriptionPipeline |
| Entity cooldown | 15s | EntityExtractor |
| Max concurrent Crustdata requests | 4 | CrustdataClient |
| Crustdata throttle polling | 200ms | CrustdataClient |
| Crustdata API version | 2025-11-01 | CrustdataClient |
| Anthropic API version | 2023-06-01 | EntityExtractor |
| Level decay factor | 0.82 | CaptionBarViewModel |
| Level decay interval | 60ms | CaptionBarViewModel |

---

## File Creation Order (Recommended)

For minimal compilation errors, create files in this order:

1. `.gitignore`, `.env`, `README.md`
2. `Info.plist`, `Coyote.entitlements`, Asset catalog
3. `EnvLoader.swift`
4. `AudioUtilities.swift`
5. `AudioTranscriptionPipeline.swift`
6. `EntityExtractor.swift`
7. `CrustdataClient.swift`
8. `CaptionBarViewModel.swift` (defines `CaptionEntry`, `PermissionError`)
9. `IntelligenceEngine.swift` (uses `CaptionEntry`)
10. `LiveMeetingCapture.swift` (uses `PermissionError`)
11. `ContentView.swift`
12. `CoyoteApp.swift`

---

## Document Index

| Document | Contents |
|----------|----------|
| **AGENTS.md** | Agent definitions, responsibilities, inputs/outputs, behavioral specs |
| **SKILL.md** | Complete source code for every file in the project |
| **PLAN.md** | This file — build order, verification steps, architecture |
