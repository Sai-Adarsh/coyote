# Coyote — Real-Time In-Meeting Intelligence

> **YC Spring 2026 RFS**: AI-Native Agencies · AI-Native Hedge Funds

A native macOS overlay that delivers live business intelligence during sales calls and investor meetings — powered by Crustdata's Person and Company APIs.

## Demo

🎥 **[Watch the demo on Loom](https://www.loom.com/share/c31875f3914b40119f80e5ac11ce476f)**

![Coyote Screenshot](Screenshot%202026-04-19%20at%204.05.59%20PM.png)

## Download

Pre-built macOS app — just mount and drag to Applications:

📦 **[Coyote.dmg](Coyote.dmg)**

## The Problem

Sales reps and investors sit through calls where dozens of names fly by — prospects, founders, portfolio companies, competitors. There's no way to research them without breaking the flow of conversation. You miss the signal that closes a deal or flags a red flag in a pitch, and spend hours after the meeting catching up on context you should have had live.

## The Solution

**Coyote** is an always-on-top macOS overlay that transcribes your meeting audio in real time, extracts every person and company mentioned, and enriches them on the fly with Crustdata's Person Search, Company Enrich, and Web Search APIs. By the time a founder finishes their pitch or a prospect names a competitor, you already have their funding history, headcount trends, LinkedIn, and latest news on screen.

## APIs

1. **OpenAI API** — `gpt-4o-transcribe` (speech-to-text), `gpt-4o-search-preview` (web-grounded live news)
2. **Anthropic Claude API** — `claude-sonnet-4-20250514` (entity extraction from transcripts)
3. **Crustdata API** — Company Search, Company Enrich, Person Search (business intelligence enrichment)

## What Powers Each Feature

- **Live Captions** — ScreenCaptureKit (mic + system audio capture) → AudioTranscriptionPipeline → OpenAI `gpt-4o-transcribe`
- **Chip Generation** — Anthropic Claude `claude-sonnet-4-20250514` via EntityExtractor — extracts person/company names from a rolling 5-caption context window with 15s cooldown dedup
- **Intelligence** — Crustdata API via CrustdataClient — Company Enrich (industry, revenue, headcount, funding) + Person Search (LinkedIn, email, title)
- **Live News** — OpenAI `gpt-4o-search-preview` with `web_search_options` for real-time web-grounded company news
