#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetMainIcon icons\disable_start_menu.ico
;@Ahk2Exe-SetName Disable WinKey Start Menu
;@Ahk2Exe-SetProductName Disable WinKey Start Menu
;@Ahk2Exe-SetDescription Stops a lone Win key press from opening the Start menu
;@Ahk2Exe-SetCompanyName Araxeus
;@Ahk2Exe-SetCopyright MIT License
;@Ahk2Exe-SetOrigFilename disable-winkey-startmenu.exe

; CI replaces this version with the release tag.
;@Ahk2Exe-SetVersion 0.0.0

if A_IsCompiled {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Quit", (*) => ExitApp())
} else {
    TraySetIcon("icons\disable_start_menu.ico")
}

LWin::Send("{LWin Down}")

; vkE8 is an unassigned key. Sending it before LWin Up stops Windows from opening Start.
LWin Up::
{
    Send("{Blind}{vkE8}{LWin Up}")
}
