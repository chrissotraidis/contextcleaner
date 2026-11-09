@echo off
rem Opens Context Cleaner with Windows PowerShell, which every Windows 10 and 11 has. Nothing to install.
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ContextCleaner.ps1"

