#Requires AutoHotkey v2.0

; The compiled exe enforces one copy with a mutex below, after any handoff.
; The #SingleInstance check would run first and see the exiting launcher as a running copy.
#SingleInstance Off

;@Ahk2Exe-SetMainIcon icons\disable_start_menu.ico
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
    A_TrayMenu.Add("Quit", (*) => ExitApp())
} else {
    TraySetIcon("icons\disable_start_menu.ico")
}

A_IconTip := "Disable WinKey Start Menu"

LWin::Send("{LWin Down}")

; vkE8 is an unassigned key. Sending it before LWin Up stops Windows from opening Start.
LWin Up::
{
    Send("{Blind}{vkE8}{LWin Up}")
}
