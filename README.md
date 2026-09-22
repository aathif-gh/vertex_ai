# Vertex AI - Meeting Assistant

> **iQOO Hackathon 2026**

Vertex AI is a real-time meeting assistant app that delivers live transcription, MoMs, summarization, and enterprise compliance tracking. 

It streams live audio to the cloud, transcribes every word as it's spoken, and uses LLMs to generate smart summaries, extract action items, and enforce enterprise compliance — all in one tap.

Say *"Hey Vertex"* at any point during a meeting to schedule events directly into Google Calendar without touching your phone.

---

##  Features

### 🔴 Live Transcription
- Streams raw PCM audio to **Deepgram** via `wss://` WebSocket for zero-latency transcription.
- **Speaker diarization** (`Speaker 0`, `Speaker 1`, ...) baked into the pipeline.
- Transcript renders word-by-word in real time.

### ⏸️ Pause & Resume
- Full pause/resume mid-meeting without losing context.
- Sends **KeepAlive frames** every 5s to hold the Deepgram connection during silences.

### 🖊️ Interactive Transcript
- **Tap** any live line to bookmark it as a critical moment.
- **Long-press** to drop an inline comment or annotation.
- Bookmarked moments are **automatically prioritized** by the AI in the final summary.

### 🤖 Smart Summary & Action Items
- On "End Meeting", the transcript is sent to **Groq LLM** for structured analysis.
- Returns a clean 3–4 bullet summary, action items with owners and deadlines, and a compliance report.

### 📄 Dual PDF Export
- **Transcript PDF**: Full diarized transcript with timestamps and speaker labels.
- **Summary PDF**: Smart summary + action items + compliance stamp.
- Shares via native OS share sheet.

### 📅 Hey Vertex — Voice Calendar
- Say *"Hey Vertex, schedule a call with Sarah on Friday at 3 PM"* during a live meeting.
- A **2-phase state machine** waits for the complete sentence before executing:
  - Phase 1 — Detects the wake phrase in the live transcript stream.
  - Phase 2 — Captures the full command from the next finalized sentence.
- Command is parsed by `llama-3.1-8b-instant` into ISO 8601 timestamps.
- A silent HTTP POST creates the real event in **Google Calendar** via REST API.
- Auth handled via a custom **OAuth 2.0 localhost loopback server** — no extra packages.

### 🛡️ Enterprise Compliance Engine
- **Deepgram-level redaction**: SSNs and card numbers are masked before they reach the device.
- **AI compliance classification**: Transcript is automatically tagged as � Confidential, 🟡 PII, or 🟢 Safe.
- Risk banner displayed in the summary UI and stamped into every exported PDF.

### 🔒 Hybrid PII Redaction
Two-layer redaction engine that runs on every AI output before display:
1. **LLM layer** — AI flags its own `sensitive_phrases[]`; Flutter replaces them with `[REDACTED]`.
2. **Regex layer** — Offline, deterministic patterns catch emails, phone numbers, and card numbers.


---

## Architecture

```
lib/
├── main.dart
├── models/
│   └── meeting_model.dart             # TranscriptEntry, ActionItem, ComplianceReport
├── screens/
│   └── meeting_screen.dart            # Live Transcript + Smart Summary tabs
├── services/
│   ├── audio_recording_service.dart   # Deepgram WebSocket + PCM stream
│   ├── llm_service.dart               # Groq: summarization, compliance, intent parsing
│   ├── pdf_generator.dart             # Dual PDF export
│   └── google_calendar_service.dart   # OAuth 2.0 + Google Calendar REST
└── widgets/
    ├── transcript_widget.dart
    └── actions_widget.dart
```

---

## API Configuration

| Service | File | Key |
|---|---|---|
| Deepgram | `audio_recording_service.dart` | `_deepgramApiKey` |
| Groq | `llm_service.dart` | `_groqApiKey` |
| Google Calendar | `google_calendar_service.dart` | `_clientId`, `_clientSecret` |

---

## Running the App

```bash
flutter pub get
```

**API keys are passed as environment variables at run time — never hardcoded.**

1. Create a file called `dart_defines.bat` in the project root:
```bat
@echo off
flutter run -d windows ^
  --dart-define=DEEPGRAM_API_KEY=your_key ^
  --dart-define=GROQ_API_KEY=your_key ^
  --dart-define=GOOGLE_CLIENT_ID=your_client_id ^
  --dart-define=GOOGLE_CLIENT_SECRET=your_client_secret
```
2. Fill in your real keys, then run it:
```powershell
.\dart_defines.bat
```
> `dart_defines.bat` is excluded from Git via `.gitignore` — your keys never get committed.

**First-time Google Calendar setup:**
1. Tap the **calendar icon** in the top-right toolbar.
2. Log in with your Google account and click **Allow**.
3. Icon turns green — you're connected. Wake-word scheduling is now live.

---

## Dependencies

| Package | Purpose |
|---|---|
| `record` | PCM microphone stream |
| `web_socket_channel` | Deepgram WebSocket |
| `dio` | Groq + Google REST calls |
| `pdf` + `printing` | PDF generation |
| `share_plus` | Native share sheet |
| `url_launcher` | Google OAuth browser flow |

---

## Built For

**iQOO Hackathon 2026** — Voice-first productivity for the world!
