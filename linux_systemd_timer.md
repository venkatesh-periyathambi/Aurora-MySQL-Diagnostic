# Linux Systemd Timer Setup (Alternative to Cron)

Systemd timers are more robust than cron: they support logging, dependency management, and automatic retry.

---

## Step 1: Create the Service Unit

Save as `/etc/systemd/system/aurora-diagnostic.service`:

```ini
[Unit]
Description=Aurora MySQL Diagnostic Collection
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/aurora-diagnostic
ExecStart=/home/ubuntu/aurora-diagnostic/scheduling/run_diagnostic.sh
StandardOutput=journal
StandardError=journal

# Security hardening
ProtectSystem=strict
ReadWritePaths=/home/ubuntu/aurora_diagnostics_output
PrivateTmp=true
NoNewPrivileges=true
```

## Step 2: Create the Timer Unit

Save as `/etc/systemd/system/aurora-diagnostic.timer`:

```ini
[Unit]
Description=Run Aurora MySQL Diagnostic every 15 minutes

[Timer]
# Run every 15 minutes
OnCalendar=*:0/15
# Randomize start within 30 seconds to avoid thundering herd
RandomizedDelaySec=30
# Run immediately if a scheduled run was missed (e.g., system was off)
Persistent=true
# Don't start if another instance is still running
AccuracySec=1s

[Install]
WantedBy=timers.target
```

## Step 3: Enable and Start

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable timer to start on boot
sudo systemctl enable aurora-diagnostic.timer

# Start the timer now
sudo systemctl start aurora-diagnostic.timer

# Verify timer is active
systemctl list-timers | grep aurora
```

## Step 4: Monitor

```bash
# Check timer status
systemctl status aurora-diagnostic.timer

# Check last run status
systemctl status aurora-diagnostic.service

# View logs
journalctl -u aurora-diagnostic.service --since "1 hour ago"
journalctl -u aurora-diagnostic.service -f  # follow live

# See next scheduled run
systemctl list-timers aurora-diagnostic.timer
```

## Common Timer Schedules

```ini
# Every 5 minutes (active troubleshooting)
OnCalendar=*:0/5

# Every 15 minutes
OnCalendar=*:0/15

# Every hour
OnCalendar=hourly

# Every 6 hours
OnCalendar=0/6:00

# Daily at 2 AM
OnCalendar=*-*-* 02:00:00

# Weekdays only, business hours (every 15 min, 8 AM - 8 PM)
OnCalendar=Mon..Fri *-*-* 08..20:0/15

# Weekly on Sunday at 3 AM
OnCalendar=Sun *-*-* 03:00:00
```

## Advantages Over Cron

| Feature | Cron | Systemd Timer |
|---------|------|---------------|
| Logging | Manual (redirect stdout) | Built-in journald |
| Missed runs | Lost forever | `Persistent=true` catches up |
| Dependencies | None | Can depend on network, mounts |
| Concurrency | Can overlap | Won't start if previous is running |
| Resource limits | None | `MemoryMax=`, `CPUQuota=` |
| Monitoring | `grep` syslog | `systemctl status` |
| Random delay | Not built-in | `RandomizedDelaySec` |
