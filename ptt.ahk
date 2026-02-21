#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; Configuration — edit these values before first run
; ==============================================================================

; Your microphone name as listed by:
;   ffmpeg -list_devices true -f dshow -i dummy
AUDIO_DEVICE := "AnkerWork B600 Video Bar (AnkerWork B600 Video Bar)"

WHISPER_EXE  := A_ScriptDir "\whisper\whisper-cli.exe"
; MODEL_PATH   := A_ScriptDir "\models\ggml-large-v3.bin"
MODEL_PATH   := A_ScriptDir "\models\ggml-large-v3-turbo.bin"
TMP_DIR      := A_ScriptDir "\tmp"
LANGUAGE     := "auto"   ; "auto" for Chinese+English, "zh", or "en"

; Initial prompt fed to whisper to encourage proper punctuation output.
; Keep it in the target language(s) with varied punctuation marks.
PROMPT       := "你好，这是一段语音输入。今天天气怎么样？很好！"

; ==============================================================================
; Startup checks
; ==============================================================================

if !FileExist(WHISPER_EXE) {
    MsgBox "whisper-cli.exe not found at:`n" WHISPER_EXE "`n`nPlace the whisper.cpp binary in the whisper\ folder.", "PTT Setup", "Icon!"
    ExitApp
}
if !FileExist(MODEL_PATH) {
    MsgBox "Model file not found at:`n" MODEL_PATH "`n`nDownload a .bin model and place it in the models\ folder.", "PTT Setup", "Icon!"
    ExitApp
}

DirCreate(TMP_DIR)

; ==============================================================================
; State
; ==============================================================================

global isRecording := false
global ffmpegProc  := 0
global warmProc    := 0   ; pre-warm process — keeps audio device open between presses
global targetWin   := 0

; ==============================================================================
; HUD overlay — dark semi-transparent pill at bottom-center of screen
; ==============================================================================

global tipGui := 0

ShowTip(text, timeout := 0, color := "FFFFFF") {
    global tipGui
    HideTip()

    g := Gui("+AlwaysOnTop -Caption")
    g.MarginX := 20
    g.MarginY := 12
    g.BackColor := "202020"
    g.SetFont("s13 bold", "Segoe UI")
    g.Add("Text", "c" color, text)

    ; Estimate window size to compute bottom-center position before Show
    ; (avoids g.Move() which silently fails in hotkey thread context)
    approxW := StrLen(text) * 9 + 40
    x := (A_ScreenWidth - approxW) // 2
    y := A_ScreenHeight - 100   ; ~100px from bottom, safely above taskbar
    g.Show("AutoSize x" x " y" y)
    tipGui := g

    if timeout > 0
        SetTimer(HideTip, -timeout)
}

HideTip() {
    global tipGui
    if IsObject(tipGui) {
        try tipGui.Destroy()
        tipGui := 0
    }
}

; ==============================================================================
; FFmpeg warm-up — keeps dshow device initialized so F8 press starts instantly
; ==============================================================================

StartWarmFFmpeg() {
    global warmProc, TMP_DIR, AUDIO_DEVICE
    warmFile := TMP_DIR "\warmup.wav"
    cmd := 'ffmpeg -f dshow -i audio="' AUDIO_DEVICE '" -ar 16000 -ac 1 -y "' warmFile '"'
    try Run(cmd, , "Hide", &pid)
    catch
        return
    warmProc := pid
}

StopWarmFFmpeg() {
    global warmProc
    if warmProc {
        ProcessClose(warmProc)   ; warmup WAV is discarded, no need for graceful stop
        warmProc := 0
    }
}

; Send Ctrl+C to a hidden FFmpeg process to flush and close the WAV properly
StopFFmpegGraceful(pid) {
    if !pid
        return
    DllCall("AttachConsole",        "UInt", pid)
    DllCall("SetConsoleCtrlHandler","Ptr",  0, "Int", true)   ; ignore Ctrl+C in AHK
    DllCall("GenerateConsoleCtrlEvent", "UInt", 0, "UInt", 0) ; send CTRL_C_EVENT
    Sleep 300
    DllCall("FreeConsole")
    DllCall("SetConsoleCtrlHandler","Ptr",  0, "Int", false)  ; restore AHK handler
}

; Clean up on exit
OnExit((*) => (HideTip(), StopWarmFFmpeg()))

; Start warming up immediately on script load
StartWarmFFmpeg()

TrayTip "PTT Ready", "Hold F8 to record", 2

; ==============================================================================
; Hotkeys
; ==============================================================================

*F8:: {
    global isRecording, ffmpegProc, warmProc, TMP_DIR, AUDIO_DEVICE, targetWin

    if isRecording
        return

    ; Save the window that should receive the pasted text
    targetWin := WinGetID("A")
    isRecording := true
    ShowTip("Preparing...", 0, "AAAAAA")

    try {
        ; Stop the warm-up process — device is already open, new process starts fast
        StopWarmFFmpeg()
        Sleep 50   ; brief gap to release the device handle

        ; FFmpeg -y flag overwrites the previous recording automatically
        wavFile := TMP_DIR "\recording.wav"

        ; Start actual recording — hidden window, stopped via GenerateConsoleCtrlEvent
        cmd := 'ffmpeg -f dshow -i audio="' AUDIO_DEVICE '" -ar 16000 -ac 1 -y "' wavFile '"'
        Run(cmd, , "Hide", &pid)
        ffmpegProc := pid

        ; Device was already warm — only a short stabilization delay needed
        Sleep 150
        ShowTip("● Recording...", 0, "FF6B6B")
    } catch as e {
        isRecording := false
        ffmpegProc := 0
        ShowTip("FFmpeg error: " e.Message, 3000, "FF6B6B")
        StartWarmFFmpeg()
    }
}

*F8 Up:: {
    global isRecording, ffmpegProc, TMP_DIR, WHISPER_EXE, MODEL_PATH, LANGUAGE, targetWin

    if !isRecording
        return

    isRecording := false
    HideTip()

    ; Stop FFmpeg recording gracefully (Ctrl+C → flushes WAV header)
    if ffmpegProc {
        StopFFmpegGraceful(ffmpegProc)
        ffmpegProc := 0
    }

    ; Restart warmup immediately so next press is also instant
    StartWarmFFmpeg()

    wavFile := TMP_DIR "\recording.wav"

    ; Require at least ~0.5s of audio (16kHz mono 16-bit = 32KB/s → ~16KB min)
    if !FileExist(wavFile) || FileGetSize(wavFile) < 16000 {
        ShowTip("Recording too short", 2000, "888888")
        return
    }

    ; Remove previous transcript and log
    txtFile := TMP_DIR "\recording.txt"
    logFile := TMP_DIR "\whisper.log"
    if FileExist(txtFile)
        FileDelete(txtFile)
    if FileExist(TMP_DIR "\recording.wav.txt")
        FileDelete(TMP_DIR "\recording.wav.txt")

    ShowTip("◌ Transcribing...", 0, "6BB5FF")

    ; Run whisper.cpp via cmd.exe to capture stdout/stderr to log file
    whisperCmd := '"' WHISPER_EXE '" -m "' MODEL_PATH '" -l ' LANGUAGE ' --output-txt --output-file "' TMP_DIR '\recording" --beam-size 1 --no-timestamps --prompt "' PROMPT '" -f "' wavFile '"'
    RunWait 'cmd.exe /c "' whisperCmd ' > "' logFile '" 2>&1"', , "Hide"

    HideTip()

    ; Some whisper.cpp builds output recording.wav.txt instead of recording.txt
    if !FileExist(txtFile) && FileExist(TMP_DIR "\recording.wav.txt")
        txtFile := TMP_DIR "\recording.wav.txt"

    if !FileExist(txtFile) {
        log := FileExist(logFile) ? FileRead(logFile) : "(no log output)"
        MsgBox "Transcription failed.`n`nwhisper.cpp output:`n" log, "PTT Error", "Icon!"
        return
    }

    text := Trim(FileRead(txtFile, "UTF-8"))

    if text = "" {
        ShowTip("No speech detected", 2000, "888888")
        return
    }

    ; Reactivate the original window (RunWait/cmd.exe may have stolen focus)
    try WinActivate(targetWin)
    Sleep 100

    ; Paste
    prevClip := A_Clipboard
    A_Clipboard := text
    if ClipWait(2) {
        Send "^v"
    } else {
        ShowTip("Clipboard error", 2000, "FF6B6B")
    }
    ; Restore previous clipboard after a short delay
    SetTimer () => (A_Clipboard := prevClip), -1500
}
