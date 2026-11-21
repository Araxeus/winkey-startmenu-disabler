#Requires AutoHotkey v2.0

; The compiled exe enforces one copy with a mutex below, after any handoff.
; The #SingleInstance check would run first and see the exiting launcher as a running copy.
#SingleInstance Off

;@Ahk2Exe-SetMainIcon icons\app.ico
;@Ahk2Exe-AddResource icons\app_paused.ico, 210
;@Ahk2Exe-SetName WinKey Start Menu Disabler
;@Ahk2Exe-SetProductName WinKey Start Menu Disabler
;@Ahk2Exe-SetDescription WinKey Start Menu Disabler
;@Ahk2Exe-SetCompanyName Araxeus
;@Ahk2Exe-SetCopyright MIT License
;@Ahk2Exe-SetOrigFilename winkey-startmenu-disabler.exe

; CI replaces this version with the release tag.
;@Ahk2Exe-SetVersion 0.0.0

if A_IsCompiled {

    ; The admin install runs this exe elevated through a scheduled task, which passes /task.
    ; Other launches hand off to that task when it exists, and otherwise run unelevated.
    fromTask := A_Args.Length && A_Args[1] = "/task"
    if !A_IsAdmin && !fromTask && RunWait('schtasks.exe /run /tn "winkey-startmenu-disabler"', , "Hide") = 0
        ExitApp

    ; One copy per session. ERROR_ACCESS_DENIED (5) means an elevated copy holds the mutex.
    DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\winkey-startmenu-disabler", "Ptr")
    if A_LastError = 183 || A_LastError = 5
        ExitApp

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Pause", TogglePause)
    A_TrayMenu.Add("Quit", (*) => ExitApp())
} else {
    A_TrayMenu.Insert("1&", "Pause", TogglePause)
    A_TrayMenu.Insert("2&")
}

; Double-clicking the tray icon runs the default item.
A_TrayMenu.Default := "Pause"
UpdateTray()

; A press already in progress at startup belongs to Windows.
winHeld := GetKeyState("LWin")
maskOnRelease := false
maskTag := 0x57534D44 ; "WSMD", carried in KEYBDINPUT.dwExtraInfo
maskedRelease := MakeMaskedRelease()
InstallInputHook(14, MouseEvent)    ; WH_MOUSE_LL
InstallInputHook(13, KeyboardEvent) ; WH_KEYBOARD_LL
Persistent()

TogglePause(*) {
    global maskOnRelease
    maskOnRelease := false
    Suspend(-1)
    A_TrayMenu.ToggleCheck("Pause")
    UpdateTray()
}

; The compiled exe holds both icons as resources: 159 is the main icon, 210 the paused one.
; Freezing stops Suspend from swapping in AutoHotkey's own suspended icon.
UpdateTray() {
    if A_IsCompiled
        TraySetIcon(A_ScriptFullPath, A_IsSuspended ? -210 : -159, true)
    else
        TraySetIcon(A_ScriptDir "\icons\app" (A_IsSuspended ? "_paused" : "") ".ico", , true)

    A_IconTip := "WinKey Start Menu Disabler" (A_IsSuspended ? " (paused)" : "")
}

InstallInputHook(kind, handler) {
    ; Both callbacks live for the lifetime of the process.
    callback := CallbackCreate(handler, "Fast")
    if !DllCall("SetWindowsHookExW", "Int", kind, "Ptr", callback,
        "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
        throw OSError()
}

KeyboardEvent(code, message, data) {
    global winHeld, maskOnRelease, maskedRelease, maskTag
    ; Ignore our replacement even if a new physical press has already started.
    if code = 0 && NumGet(data, 16, "UPtr") != maskTag {
        vk := NumGet(data, "UInt")
        if vk != 0x5B { ; Any other key uses or modifies the hold.
            maskOnRelease := false
        } else if NumGet(data, 8, "UInt") & 0x80 { ; LLKHF_UP
            mask := maskOnRelease && !A_IsSuspended
            winHeld := maskOnRelease := false
            ; Suppress the original up only if Windows accepted the entire replacement.
            if mask && DllCall("SendInput", "UInt", 3, "Ptr", maskedRelease,
                "Int", maskedRelease.Size // 3, "UInt") = 3
                return 1
        } else if !winHeld {
            ; Repeated Win downs must preserve any shortcut or click seen during this hold.
            winHeld := true
            maskOnRelease := !A_IsSuspended && !GetKeyState("Shift") && !GetKeyState("Ctrl")
                && !GetKeyState("Alt") && !GetKeyState("RWin")
        }
    }
    return NextInputHook(code, message, data)
}

MouseEvent(code, message, data) {
    global maskOnRelease
    ; Moving the pointer is part of aiming Click to Do. A button or wheel uses the hold.
    if code = 0 && message != 0x0200 ; WM_MOUSEMOVE
        maskOnRelease := false
    return NextInputHook(code, message, data)
}

NextInputHook(code, message, data) {
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", code, "UPtr", message, "Ptr", data, "Ptr")
}

MakeMaskedRelease() {
    global maskTag
    ; One SendInput batch keeps the unassigned key before LWin up, including on a fast tap.
    size := A_PtrSize = 8 ? 40 : 28 ; sizeof(INPUT)
    events := Buffer(3 * size, 0)
    for i, vk in [0xE8, 0xE8, 0x5B] {
        offset := (i - 1) * size
        NumPut("UInt", 1, events, offset) ; INPUT_KEYBOARD
        NumPut("UShort", vk, events, offset + A_PtrSize)
        NumPut("UPtr", maskTag, events, offset + (A_PtrSize = 8 ? 24 : 16))
    }
    NumPut("UInt", 2, events, size + A_PtrSize + 4) ; KEYEVENTF_KEYUP
    NumPut("UShort", 0x5B, "UInt", 3, events, 2 * size + A_PtrSize + 2) ; extended LWin up
    return events
}
