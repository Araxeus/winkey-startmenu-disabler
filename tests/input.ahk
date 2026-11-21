#Requires AutoHotkey v2.0
#SingleInstance Off

; Use the app's decision logic with a known modifier state on a headless runner.
class TestHold extends WinKeyHold {
    modified := false
    ModifierDown() => this.modified
}

; Each keyboard event is [virtual key, is key up]. Mouse events use their WM_* code.
; A zero maskAt means every event in the sequence should pass through.
CheckSequence(name, events, maskAt := 0, hold := unset) {
    if !IsSet(hold)
        hold := TestHold()
    for index, event in events {
        if event is Array {
            mask := hold.Keyboard(event*)
            if mask != (index = maskAt)
                throw Error(name " at event " index ": expected " (index = maskAt ? "mask" : "pass")
                    ", got " (mask ? "mask" : "pass"))
        } else {
            hold.Mouse(event)
        }
    }
    FileAppend("PASS " name Chr(10), "*")
}

try {
    winDown := [0x5B, false]
    winUp := [0x5B, true]
    move := 0x200, leftDown := 0x201, leftUp := 0x202

    CheckSequence("bare tap", [winDown, winUp], 2)
    CheckSequence("hold while aiming", [winDown, move, winDown, move, winUp], 5)
    for name, vk in Map("Win+V", 0x56, "Win+period", 0xBE) {
        keyDown := [vk, false], keyUp := [vk, true]
        CheckSequence(name " released Win first", [winDown, keyDown, winUp, keyUp])
        CheckSequence(name " released shortcut key first", [winDown, keyDown, keyUp, winUp])
    }
    CheckSequence("Win+click, then repeat", [winDown, leftDown, leftUp, winDown, winUp])
    CheckSequence("release Win while clicking", [winDown, leftDown, winUp, leftUp])
    CheckSequence("Win+wheel", [winDown, 0x20A, winUp])
    CheckSequence("right Win", [[0x5C, false], [0x5C, true]])
    CheckSequence("Win already down at startup", [winDown, winUp], 0, TestHold(true))

    hold := TestHold()
    hold.modified := true
    CheckSequence("modified Win press", [winDown, winUp], 0, hold)
    hold.modified := false
    CheckSequence("next bare tap", [winDown, winUp], 2, hold)

    Suspend(true)
    CheckSequence("paused Win press", [winDown, winUp])
    Suspend(false)

    ; TogglePause cancels the pending mask on both pause and resume.
    CheckSequence("start a hold", [winDown], 0, hold)
    hold.CancelMask()
    CheckSequence("release after pause and resume", [winDown, winUp], 0, hold)
} catch Error as err {
    FileAppend("FAIL " err.Message Chr(10) err.Stack Chr(10), "**")
    ExitApp(1)
}
ExitApp(0)

; Include definitions from the shipping script. Exit above its tray and hook startup code.
#Include ..\winkey-startmenu-disabler.ahk
