' start-watchers.vbs — launch Zebar and both background watchers with no
' console window.
'
' Task Scheduler:
'   Program:   wscript.exe
'   Arguments: "C:\Users\zaina\.local\bin\start-watchers.vbs"
'   Trigger:   At log on, delay 60 seconds
'   Run only when user is logged on
'
' The third Run() argument (0) is the window style: hidden. This works where
' -WindowStyle Hidden and mintty -w hide do not, because no console is ever
' allocated in the first place.

Option Explicit

Dim shell, home, ps1, bashExe, walsync, zebarExe

Set shell = CreateObject("WScript.Shell")
home = shell.ExpandEnvironmentStrings("%USERPROFILE%")

' --- Adjust these if your paths differ ---
bashExe  = "C:\msys64\usr\bin\bash.exe"
walsync  = "~/.local/share/chezmoi/scripts/walsync.sh"
zebarExe = "C:\Program Files\glzr.io\Zebar\zebar.exe"
' -----------------------------------------

ps1 = home & "\.local\bin\Hide-TaskbarOnMonitor.ps1"

' 1. The status bar. GlazeWM used to launch this via startup_commands.
shell.Run """" & zebarExe & """", 0, False

' 2. Keep the dock hidden on the portrait monitor.
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """ -Watch", 0, False

' 3. Repaint the palette when the Wallpaper Engine wallpaper changes.
shell.Run """" & bashExe & """ -lc """ & walsync & " watch""", 0, False

Set shell = Nothing
