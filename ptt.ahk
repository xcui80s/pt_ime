#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; Configuration — edit these values before first run
; ==============================================================================

; Your microphone name as listed by:
;   ffmpeg -list_devices true -f dshow -i dummy
AUDIO_DEVICE := "AnkerWork B600 Video Bar (AnkerWork B600 Video Bar)"

; whisper.cpp server — run start_whisper_server.bat on the GPU machine first
; Set WHISPER_HOST to "127.0.0.1" if the server runs on this machine,
; or the server's LAN IP (e.g. "192.168.1.10") for remote transcription.
WHISPER_HOST := "127.0.0.1"
WHISPER_PORT := 8989

TMP_DIR      := A_ScriptDir "\tmp"
WAV_BASENAME := "recording"   ; base name prefix — timestamp suffix added per press
LANGUAGE     := "auto"   ; "auto" for Chinese+English, "zh", or "en"
PROMPT       := "输出简体中文。你好，这是一段语音输入。今天天气怎么样？很好！"


DirCreate(TMP_DIR)

; ==============================================================================
; State
; ==============================================================================

global isRecording    := false
global ffmpegProc     := 0
global warmProc       := 0   ; pre-warm process — keeps audio device open between presses
global targetWin      := 0
global sessionWavFile := ""  ; WAV path for the current recording session
global sessionTxtFile := ""  ; transcript path for the current recording session

; ==============================================================================
; HUD overlay — dark semi-transparent pill at bottom-center of screen
; ==============================================================================

global tipGui := 0

ShowTip(text, timeout := 0, color := "EEEEEE") {
    global tipGui
    HideTip()

    g := Gui("+AlwaysOnTop -Caption")
    g.MarginX := 24
    g.MarginY := 14
    g.BackColor := "181818"
    g.SetFont("s13 bold", "Segoe UI")
    g.Add("Text", "c" color " Center", text)

    ; Pre-compute bottom-center position (g.Move() silently fails in hotkey context)
    approxW := StrLen(text) * 9 + 48
    x := (A_ScreenWidth - approxW) // 2
    y := A_ScreenHeight - 110
    g.Show("AutoSize x" x " y" y)
    tipGui := g

    ; Rounded pill corners — read actual window size after Show
    WinGetPos(, , &w, &h, g)
    if (w > 0 && h > 0) {
        hRgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0,
                        "Int", w+1, "Int", h+1, "Int", 26, "Int", 26, "Ptr")
        DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", hRgn, "Int", true)
    }

    ; iOS dark-mode acrylic frosted glass (Windows 10 1803+)
    ; GradientColor ABGR: 0x80181818 = dark grey tint at ~50% over blurred background
    ap := Buffer(16, 0)
    NumPut("UInt", 4,          ap, 0)   ; ACCENT_ENABLE_ACRYLICBLURBEHIND
    NumPut("UInt", 2,          ap, 4)   ; AccentFlags
    NumPut("UInt", 0x80181818, ap, 8)   ; GradientColor (ABGR)

    ; WINCOMPATTRDATA: { DWORD attr, [pad on x64], PVOID data, SIZE_T size }
    wca := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
    NumPut("UInt", 19,      wca, 0)
    NumPut("Ptr",  ap.Ptr,  wca, A_PtrSize = 8 ? 8 : 4)
    NumPut("UInt", 16,      wca, A_PtrSize = 8 ? 16 : 8)
    DllCall("user32\SetWindowCompositionAttribute", "Ptr", g.Hwnd, "Ptr", wca)

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
    DllCall("FreeConsole")                                       ; must detach first or AttachConsole fails
    DllCall("AttachConsole",            "UInt", pid)
    DllCall("SetConsoleCtrlHandler",    "Ptr",  0, "Int", true)  ; AHK ignores Ctrl+C
    DllCall("GenerateConsoleCtrlEvent", "UInt", 0, "UInt", 0)    ; send to FFmpeg's console group
    DllCall("FreeConsole")
    DllCall("SetConsoleCtrlHandler",    "Ptr",  0, "Int", false) ; restore
    ProcessWaitClose(pid, 3)                                     ; wait up to 3s for FFmpeg to flush & exit
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
    global isRecording, ffmpegProc, warmProc, WAV_BASENAME, TMP_DIR, AUDIO_DEVICE, targetWin, sessionWavFile, sessionTxtFile

    if isRecording
        return

    ; Save the window that should receive the pasted text
    targetWin := WinGetID("A")
    isRecording := true
    ShowTip("Preparing...", 0, "AAAAAA")

    try {
        ; Build timestamped paths for this session
        _ts := FormatTime(, "yyyyMMdd_HHmmss")
        sessionWavFile := TMP_DIR "\" WAV_BASENAME "_" _ts ".wav"
        sessionTxtFile := TMP_DIR "\" WAV_BASENAME "_" _ts "_transcript.txt"

        ; Stop the warm-up process — device is already open, new process starts fast
        StopWarmFFmpeg()
        Sleep 50   ; brief gap to release the device handle

        ; Start actual recording — hidden window, stopped via GenerateConsoleCtrlEvent
        cmd := 'ffmpeg -f dshow -i audio="' AUDIO_DEVICE '" -ar 16000 -ac 1 -y "' sessionWavFile '"'
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
    global isRecording, ffmpegProc, sessionWavFile, sessionTxtFile, TMP_DIR, WHISPER_HOST, WHISPER_PORT, LANGUAGE, PROMPT, targetWin

    if !isRecording
        return

    isRecording := false
    HideTip()

    ; Stop FFmpeg recording gracefully (Ctrl+C → flushes WAV header)
    ; ProcessWaitClose inside StopFFmpegGraceful ensures the file is fully written
    if ffmpegProc {
        StopFFmpegGraceful(ffmpegProc)
        ffmpegProc := 0
    }

    ; Restart warmup immediately so next press is also instant
    StartWarmFFmpeg()

    ; Require at least ~0.5s of audio (16kHz mono 16-bit = 32KB/s → ~16KB min)
    if !FileExist(sessionWavFile) || FileGetSize(sessionWavFile) < 16000 {
        ShowTip("Recording too short", 2000, "AAAAAA")
        return
    }

    ShowTip("◌ Transcribing...", 0, "6BB5FF")

    ; POST WAV to whisper.cpp server; response_format=text returns plain transcription
    logFile := TMP_DIR "\whisper.log"
    langParam := (LANGUAGE = "auto") ? "" : " -F language=" LANGUAGE
    RunWait 'cmd.exe /c curl -s --max-time 30 -X POST http://' WHISPER_HOST ':' WHISPER_PORT '/inference'
          . ' -F file=@"' sessionWavFile '"'
          . langParam
          . ' -F response_format=text'
          . ' -F "prompt=' PROMPT '"'
          . ' > "' logFile '" 2>&1', , "Hide"

    HideTip()

    text := Trim(FileRead(logFile, "UTF-8"))
    if text = "" || SubStr(text, 1, 6) = "curl: " {
        ShowTip("Transcription failed", 2000, "FF6B6B")
        return
    }

    ; Persist transcript locally alongside the WAV file
    FileAppend text "`n", sessionTxtFile, "UTF-8"

    if text = "" {
        ShowTip("No speech detected", 2000, "AAAAAA")
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
