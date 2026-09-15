' Hidden launcher for IpPreset GUI (no console window).
' Called from IpPreset.cmd after Unblock-File.
Option Explicit
Dim sh, fso, dir, ps1, cmd, i, a, q
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\IpPreset.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File " & Quote(ps1)
For i = 0 To WScript.Arguments.Count - 1
  a = WScript.Arguments(i)
  If Left(a, 1) = "-" Then
    cmd = cmd & " " & a
  Else
    cmd = cmd & " " & Quote(a)
  End If
Next
' WindowStyle 0 = hidden; False = do not wait (GUI owns lifetime)
sh.Run cmd, 0, False

Function Quote(s)
  Quote = """" & Replace(s, """", """""") & """"
End Function
