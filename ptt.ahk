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
; Tooltip — fixed at bottom-center of primary monitor
; ==============================================================================

ShowTip(text, timeout := 0) {
    w := StrLen(text) * 8 + 24   ; rough pixel width estimate
    x := (A_ScreenWidth  - w)  // 2
    y :=  A_ScreenHeight - 80
    ToolTip(text, x, y)
    if timeout > 0
        SetTimer(() => ToolTip(), -timeout)
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
OnExit((*) => StopWarmFFmpeg())

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

    ; Stop the warm-up process — device is already open, new process starts fast
    StopWarmFFmpeg()
    Sleep 50   ; brief gap to release the device handle

    ; Remove previous recording
    wavFile := TMP_DIR "\recording.wav"
    if FileExist(wavFile)
        FileDelete(wavFile)

    ; Start actual recording — hidden window, stopped via GenerateConsoleCtrlEvent
    cmd := 'ffmpeg -f dshow -i audio="' AUDIO_DEVICE '" -ar 16000 -ac 1 -y "' wavFile '"'
    try Run(cmd, , "Hide", &pid)
    catch as e {
        isRecording := false
        ShowTip("FFmpeg error: " e.Message, 3000)
        StartWarmFFmpeg()
        return
    }
    ffmpegProc := pid

    ; Device was already warm — only a short stabilization delay needed
    Sleep 150
    ShowTip("Recording...")
}

*F8 Up:: {
    global isRecording, ffmpegProc, TMP_DIR, WHISPER_EXE, MODEL_PATH, LANGUAGE, targetWin

    if !isRecording
        return

    isRecording := false
    ToolTip()  ; clear

    ; Stop FFmpeg recording gracefully (Ctrl+C → flushes WAV header)
    if ffmpegProc {
        StopFFmpegGraceful(ffmpegProc)
        ffmpegProc := 0
    }

    ; Restart warmup immediately so next press is also instant
    StartWarmFFmpeg()

    wavFile := TMP_DIR "\recording.wav"

    if !FileExist(wavFile) {
        ShowTip("Recording failed", 2000)
        return
    }

    ; Remove previous transcript and log
    txtFile := TMP_DIR "\recording.txt"
    logFile := TMP_DIR "\whisper.log"
    if FileExist(txtFile)
        FileDelete(txtFile)
    if FileExist(TMP_DIR "\recording.wav.txt")
        FileDelete(TMP_DIR "\recording.wav.txt")

    ShowTip("Transcribing...")

    ; Run whisper.cpp via cmd.exe to capture stdout/stderr to log file
    whisperCmd := '"' WHISPER_EXE '" -m "' MODEL_PATH '" -l ' LANGUAGE ' --output-txt --output-file "' TMP_DIR '\recording" --beam-size 1 --no-timestamps -f "' wavFile '"'
    RunWait 'cmd.exe /c "' whisperCmd ' > "' logFile '" 2>&1"', , "Hide"

    ToolTip()  ; clear

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
        ShowTip("No speech detected", 2000)
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
        ShowTip("Clipboard error", 2000)
    }
    ; Restore previous clipboard after a short delay
    SetTimer () => (A_Clipboard := prevClip), -1500
}
