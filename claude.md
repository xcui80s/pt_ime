# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Whisper PTT Voice Input (Windows)

## Project Overview

This project implements a local Push-to-Talk voice typing system on Windows using:

- whisper.cpp (CUDA accelerated)
- AutoHotkey v2 (hotkey automation)
- FFmpeg (audio capture)

The system allows:

Press key → Speak → Release key → Text auto-inserted at cursor

Supports:
- Chinese + English mixed input
- Local GPU acceleration
- Low latency transcription

---

## Architecture

F8 (hold)
   ↓
FFmpeg recording
   ↓
Release F8
   ↓
Stop recording
   ↓
whisper.cpp transcription (CUDA)
   ↓
Copy to clipboard
   ↓
Auto paste to active window

---

## Directory Structure

```
pt_ime/
├── ptt.ahk          # Main AutoHotkey v2 script — hotkey, FFmpeg control, clipboard, paste
├── whisper/         # whisper.cpp binaries (main.exe or whisper-cli.exe)
├── models/          # GGUF model files (e.g. ggml-large-v3.bin)
└── tmp/             # Temporary audio files (e.g. recording.wav), gitignored
```

---

## Setup

Prerequisites:
1. **AutoHotkey v2** — install from https://www.autohotkey.com/
2. **whisper.cpp** (CUDA build) — build from source or download a pre-built binary; place under `whisper/`
3. **Model file** — download a `.bin` model (e.g. `ggml-large-v3`) and place under `models/`
4. **FFmpeg** — must be on system PATH (`ffmpeg -version` should work)

To run: double-click `ptt.ahk` (or right-click → Run with AutoHotkey)

---

## Key Implementation Notes

**FFmpeg audio capture (WAV, mono, 16kHz for whisper):**
```
ffmpeg -f dshow -i audio="Microphone Device Name" -ar 16000 -ac 1 tmp\recording.wav
```

**whisper.cpp transcription:**
```
whisper\whisper-cli.exe -m models\ggml-large-v3.bin -l auto --output-txt -f tmp\recording.wav
```
- Use `-l zh` to force Chinese, `-l en` for English, or `-l auto` for auto-detect
- For mixed Chinese/English, `--language auto` works well

**AutoHotkey clipboard paste pattern:**
```ahk
A_Clipboard := transcribedText
Send "^v"
```
