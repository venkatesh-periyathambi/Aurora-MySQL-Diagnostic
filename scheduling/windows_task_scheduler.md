# Windows Task Scheduler Setup

Schedule Aurora MySQL diagnostics on Windows using Task Scheduler.

## Prerequisites

- MySQL client installed (e.g., `C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe`)
- Network access to Aurora cluster from your Windows machine
- PowerShell 5.1+ or Command Prompt

---

## Step 1: Create the Batch Script

Save as `C:\aurora-diagnostic\run_diagnostic.bat`:

```batch
@echo off
REM ============================================================================
REM Aurora MySQL Diagnostic - Windows Scheduled Task
REM ============================================================================

SET AURORA_HOST=aurora8.cluster-xxxxx.region.rds.amazonaws.com
SET AURORA_USER=admin
SET AURORA_PASS=your_password
SET AURORA_DB=qldwh
SET MYSQL_EXE="C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
SET SCRIPT_DIR=C:\aurora-diagnostic\diagnostics
SET OUTPUT_DIR=C:\aurora-diagnostic\output

REM Create output directory if needed
IF NOT EXIST "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM Generate timestamp
FOR /f "tokens=2 delims==" %%I IN ('wmic os get localdatetime /value') DO SET datetime=%%I
SET TIMESTAMP=%datetime:~0,8%_%datetime:~8,6%

REM Set password via environment variable (avoids command-line exposure)
SET MYSQL_PWD=%AURORA_PASS%

REM Run diagnostic
%MYSQL_EXE% -h %AURORA_HOST% -u %AURORA_USER% %AURORA_DB% < "%SCRIPT_DIR%\aurora_mysql_diagnostic_locks_latches.sql" > "%OUTPUT_DIR%\diag_%TIMESTAMP%.txt" 2>&1

REM Log result
echo [%TIMESTAMP%] diagnostic exit=%ERRORLEVEL% >> "%OUTPUT_DIR%\task_history.log"

REM Cleanup files older than 7 days
FORFILES /P "%OUTPUT_DIR%" /S /D -7 /C "cmd /c del @path" 2>nul

exit /b %ERRORLEVEL%
```

## Step 2: Create PowerShell Alternative (Recommended)

Save as `C:\aurora-diagnostic\run_diagnostic.ps1`:

```powershell
# ============================================================================
# Aurora MySQL Diagnostic - PowerShell Scheduled Task
# ============================================================================

$Config = @{
    AuroraHost    = "aurora8.cluster-xxxxx.region.rds.amazonaws.com"
    AuroraUser    = "admin"
    AuroraPass    = "your_password"
    AuroraDB      = "qldwh"
    MysqlExe      = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
    ScriptDir     = "C:\aurora-diagnostic\diagnostics"
    OutputDir     = "C:\aurora-diagnostic\output"
    RetentionDays = 7
}

# Create output directory
New-Item -ItemType Directory -Force -Path $Config.OutputDir | Out-Null

# Generate timestamp
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path $Config.OutputDir "diag_$Timestamp.txt"
$LogFile = Join-Path $Config.OutputDir "task_history.log"

# Set password as environment variable
$env:MYSQL_PWD = $Config.AuroraPass

# Run diagnostic
$SqlFile = Join-Path $Config.ScriptDir "aurora_mysql_diagnostic_locks_latches.sql"
$Process = Start-Process -FilePath $Config.MysqlExe `
    -ArgumentList "-h", $Config.AuroraHost, "-u", $Config.AuroraUser, $Config.AuroraDB `
    -RedirectStandardInput $SqlFile `
    -RedirectStandardOutput $OutputFile `
    -RedirectStandardError "$OutputFile.err" `
    -NoNewWindow -Wait -PassThru

# Log result
$LogEntry = "[$Timestamp] diagnostic exit=$($Process.ExitCode) output=$OutputFile"
Add-Content -Path $LogFile -Value $LogEntry

# Cleanup old files
Get-ChildItem -Path $Config.OutputDir -File |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Config.RetentionDays) } |
    Remove-Item -Force

# Clear password from environment
Remove-Item Env:\MYSQL_PWD

Write-Host $LogEntry
exit $Process.ExitCode
```

---

## Step 3: Create the Scheduled Task

### Option A: Task Scheduler GUI

1. Open **Task Scheduler** (`taskschd.msc`)
2. Click **Create Task** (not Basic Task)
3. **General tab:**
   - Name: `Aurora MySQL Diagnostic`
   - Run whether user is logged on or not
   - Run with highest privileges
4. **Triggers tab → New:**
   - Begin the task: On a schedule
   - Settings: Daily, repeat every **15 minutes** for a duration of **1 day**
   - Or: Every 5 minutes for active troubleshooting
5. **Actions tab → New:**
   - Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\aurora-diagnostic\run_diagnostic.ps1"`
6. **Settings tab:**
   - Allow task to be run on demand
   - If the task is already running: Do not start a new instance
7. Click **OK**, enter your Windows password when prompted

### Option B: Command Line (schtasks)

```cmd
REM Every 15 minutes
schtasks /create /tn "Aurora MySQL Diagnostic" /tr "powershell.exe -ExecutionPolicy Bypass -File C:\aurora-diagnostic\run_diagnostic.ps1" /sc minute /mo 15 /ru SYSTEM

REM Every 5 minutes (active troubleshooting)
schtasks /create /tn "Aurora MySQL Diagnostic - Frequent" /tr "powershell.exe -ExecutionPolicy Bypass -File C:\aurora-diagnostic\run_diagnostic.ps1" /sc minute /mo 5 /ru SYSTEM

REM Daily at 2 AM (lock test - test environments only)
schtasks /create /tn "Aurora Lock Contention Test" /tr "C:\aurora-diagnostic\run_lock_test.bat" /sc daily /st 02:00 /ru SYSTEM
```

### Option C: PowerShell (Register-ScheduledTask)

```powershell
# Create the trigger (every 15 minutes)
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Days 365)

# Create the action
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "C:\aurora-diagnostic\run_diagnostic.ps1"'

# Create settings
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

# Register the task
Register-ScheduledTask `
    -TaskName "Aurora MySQL Diagnostic" `
    -Trigger $Trigger `
    -Action $Action `
    -Settings $Settings `
    -RunLevel Highest `
    -Description "Captures Aurora MySQL lock and performance diagnostics every 15 minutes"

# Verify
Get-ScheduledTask -TaskName "Aurora MySQL Diagnostic" | Format-List
```

---

## Managing Scheduled Tasks

```powershell
# List Aurora tasks
Get-ScheduledTask | Where-Object { $_.TaskName -like "*Aurora*" }

# Run task immediately
Start-ScheduledTask -TaskName "Aurora MySQL Diagnostic"

# Check last run result
Get-ScheduledTaskInfo -TaskName "Aurora MySQL Diagnostic"

# Disable task (e.g., after troubleshooting)
Disable-ScheduledTask -TaskName "Aurora MySQL Diagnostic"

# Re-enable
Enable-ScheduledTask -TaskName "Aurora MySQL Diagnostic"

# Delete task
Unregister-ScheduledTask -TaskName "Aurora MySQL Diagnostic" -Confirm:$false
```

```cmd
REM Command Prompt equivalents
schtasks /query /tn "Aurora MySQL Diagnostic"
schtasks /run /tn "Aurora MySQL Diagnostic"
schtasks /end /tn "Aurora MySQL Diagnostic"
schtasks /delete /tn "Aurora MySQL Diagnostic" /f
```

---

## Security Considerations

1. **Credential Storage:** Store the password in Windows Credential Manager instead of plaintext:
   ```powershell
   # Store credential
   cmdkey /add:aurora-diagnostic /user:admin /pass:your_password

   # Retrieve in script
   $Cred = cmdkey /list:aurora-diagnostic
   ```

2. **File Permissions:** Restrict access to the config directory:
   ```powershell
   icacls "C:\aurora-diagnostic" /inheritance:r /grant:r "$env:USERNAME:(OI)(CI)F"
   ```

3. **Run As:** Use a dedicated service account with minimal permissions.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `mysql` not found | Add MySQL bin to PATH or use full path in script |
| Access denied | Check security group allows your Windows IP on port 3306 |
| Task runs but no output | Check `task_history.log` and Windows Event Viewer |
| Execution policy error | Use `-ExecutionPolicy Bypass` in the action arguments |
| Task shows 0x1 (error) | Check output `.err` file for MySQL connection errors |
