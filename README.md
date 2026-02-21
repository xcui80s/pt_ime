# Whisper PTT Voice Input (Windows)

Local Push-to-Talk voice typing using whisper.cpp + AutoHotkey + FFmpeg.
Hold **F8** → speak → release → text is typed at your cursor.

---

## Requirements

- Windows 10/11
- NVIDIA GPU (CUDA) recommended for fast transcription
- ~3 GB disk space for model file

---

## Step-by-Step Setup

### Step 1 — Install AutoHotkey v2

1. Go to https://www.autohotkey.com/ and download **AutoHotkey v2**
2. Run the installer with default settings
3. Verify: right-click any `.ahk` file → you should see "Run script" in the menu

---

### Step 2 — Install FFmpeg

1. Go to https://ffmpeg.org/download.html → Windows → **gyan.dev** builds → download `ffmpeg-release-essentials.zip`
2. Extract the zip, rename the folder to `ffmpeg`, and move it to `C:\ffmpeg`
3. Add FFmpeg to PATH:
   - Open Start → search "Environment Variables" → click "Edit the system environment variables"
   - Click **Environment Variables** → under "System variables" find `Path` → click **Edit**
   - Click **New** → type `C:\ffmpeg\bin` → click OK on all dialogs
4. Verify: open a new Command Prompt and run:
   ```
   ffmpeg -version
   ```
   You should see version info, not "not recognized".

---

### Step 3 — Get whisper.cpp binary (CUDA build)

**Option A — Pre-built binary (recommended):**
1. Go to https://github.com/ggerganov/whisper.cpp/releases
2. Download the latest `whisper-cublas-*-x64.zip` (CUDA version) or `whisper-*-x64.zip` (CPU-only)
3. Extract and copy `whisper-cli.exe` (and any `.dll` files alongside it) into the `whisper\` folder of this project:
   ```
   pt_ime\
   └── whisper\
       ├── whisper-cli.exe
       └── *.dll  (cublas, cudart, etc.)
   ```

**Option B — CPU-only fallback:**
If you don't have an NVIDIA GPU, download the non-CUDA zip. Transcription will be slower (~5–15s for a short phrase).

---

### Step 4 — Download a model

1. Go to https://huggingface.co/ggerganov/whisper.cpp and download a model:
   - `ggml-large-v3.bin` — best accuracy for Chinese+English (~3 GB)
   - `ggml-medium.bin` — good balance of speed and accuracy (~1.5 GB)
   - `ggml-base.bin` — fastest, lower accuracy (~150 MB)
2. Place the downloaded `.bin` file in the `models\` folder:
   ```
   pt_ime\
   └── models\
       └── ggml-large-v3.bin
   ```
3. If you chose a different model, update `MODEL_PATH` in `ptt.ahk` (see Step 6).

---

### Step 5 — Find your microphone name

Open Command Prompt and run:
```
ffmpeg -list_devices true -f dshow -i dummy
```

Look for lines like:
```
[dshow @ ...] "Microphone (AnkerWork B600 Video Bar)" (audio)
```

Copy the exact name in quotes (including "Microphone (...)").

---

### Step 6 — Configure ptt.ahk

Open `ptt.ahk` in any text editor and edit the top section:

```ahk
AUDIO_DEVICE := "Microphone (Your Device Name Here)"   ; ← paste your device name
MODEL_PATH   := A_ScriptDir "\models\ggml-large-v3.bin" ; ← update if using a different model
LANGUAGE     := "auto"                                  ; "auto", "zh", or "en"
```

---

### Step 7 — Run

Double-click `ptt.ahk`. A tray icon will appear.

- **Hold F8** to start recording (tooltip: "Recording...")
- **Release F8** to stop and transcribe (tooltip: "Transcribing...")
- Text is automatically pasted into the active window

To exit: right-click the tray icon → Exit.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "whisper-cli.exe not found" on startup | Check that the file is in `whisper\` folder |
| "Model file not found" on startup | Check that the `.bin` file is in `models\` folder |
| Recording produces no audio | Verify the device name exactly matches Step 5 output |
| `ffmpeg` not recognized | Re-check PATH setup in Step 2, open a **new** terminal after editing |
| Transcription is slow | Use a smaller model (`ggml-medium.bin`) or ensure CUDA DLLs are present |
| F8 doesn't trigger recording | Ensure no other app has captured F8 as a global hotkey |
