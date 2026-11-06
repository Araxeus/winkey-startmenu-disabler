#Requires AutoHotkey v2.0

; The compiled exe enforces one copy with a mutex below, after any handoff.
; The #SingleInstance check would run first and see the exiting launcher as a running copy.
#SingleInstance Off

;@Ahk2Exe-SetMainIcon icons\disable_start_menu.ico
;@Ahk2Exe-AddResource icons\disable_start_menu_paused.ico, 210
;@Ahk2Exe-SetName Disable WinKey Start Menu
;@Ahk2Exe-SetProductName Disable WinKey Start Menu
;@Ahk2Exe-SetDescription Disable WinKey Start Menu
;@Ahk2Exe-SetCompanyName Araxeus
;@Ahk2Exe-SetCopyright MIT License
;@Ahk2Exe-SetOrigFilename disable-winkey-startmenu.exe

; CI replaces this version with the release tag.
;@Ahk2Exe-SetVersion 0.0.0

if A_IsCompiled {

    ; The admin install runs this exe elevated through a scheduled task, which passes /task.
    ; Other launches hand off to that task when it exists, and otherwise run unelevated.
    fromTask := A_Args.Length && A_Args[1] = "/task"
    if !A_IsAdmin && !fromTask && RunWait('schtasks.exe /run /tn "disable-winkey-startmenu"', , "Hide") = 0
        ExitApp

    ; One copy per session. ERROR_ACCESS_DENIED (5) means an elevated copy holds the mutex.
    DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\disable-winkey-startmenu", "Ptr")
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

TogglePause(*) {
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
        TraySetIcon(A_ScriptDir "\icons\disable_start_menu" (A_IsSuspended ? "_paused" : "") ".ico", , true)

    A_IconTip := "Disable WinKey Start Menu" (A_IsSuspended ? " (paused)" : "")
}

LWin::Send("{LWin Down}")

; vkE8 is an unassigned key. Sending it before LWin Up stops Windows from opening Start.
LWin Up::
{
    Send("{Blind}{vkE8}{LWin Up}")
}
