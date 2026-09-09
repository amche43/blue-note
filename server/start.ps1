param([string]$BindAddress='127.0.0.1', [int]$Port=8787)
$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
if (-not $env:BLUE_NOTE_TOKEN -or $env:BLUE_NOTE_TOKEN.Length -lt 32) {
  throw '请先设置至少 32 字符的 BLUE_NOTE_TOKEN，两个设备使用同一个口令。'
}
$env:BLUE_NOTE_BIND=$BindAddress
$env:BLUE_NOTE_PORT=$Port.ToString()
java --add-modules jdk.httpserver BlueNoteServer.java
