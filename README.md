<p align="center">
  <img src="https://img.shields.io/badge/Amazon%20Aurora-527FFF?style=for-the-badge&logo=amazon-aws&logoColor=white" alt="Aurora MySQL"/>
  <img src="https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white" alt="MySQL"/>
  <img src="https://img.shields.io/badge/Performance_Schema-FF6B35?style=for-the-badge&logo=databricks&logoColor=white" alt="Performance Schema"/>
  <img src="https://img.shields.io/badge/InnoDB_Locks-DC382D?style=for-the-badge&logo=redis&logoColor=white" alt="InnoDB Locks"/>
</p>

<h1 align="center">Aurora MySQL Diagnostic Toolkit</h1>

<p align="center">
  <em>Comprehensive diagnostic and stress-testing toolkit for troubleshooting lock contention, latches, and parallel query degradation on Aurora MySQL and Community MySQL.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Aurora_MySQL-3.x_(8.0_compatible)-527FFF?style=flat-square" alt="Aurora 3.x"/>
  <img src="https://img.shields.io/badge/MySQL-8.4-4479A1?style=flat-square" alt="MySQL 8.4"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License"/>
  <img src="https://img.shields.io/badge/Status-Production_Ready-brightgreen?style=flat-square" alt="Production Ready"/>
</p>

---

## Problem Statement

> A query works perfectly when executed individually but **degrades, blocks, or fails when run in parallel** (e.g., 100 concurrent sessions).

This toolkit helps you:
- **Diagnose** lock contention, gap locks, deadlocks, and latch waits in real-time
- **Simulate** realistic lock contention scenarios to reproduce the issue
- **Capture** live metrics while parallel workloads are running
- **Identify** root causes: gap locks, missing indexes, long transactions, resource saturation

---

## Repository Structure

```
aurora-diagnostic/
│
├── diagnostics/                                    ← Production-safe diagnostic scripts
│   ├── aurora_mysql_diagnostic_locks_latches.sql   ← Aurora MySQL 3.x (25 sections + recommendations)
│   ├── mysql_diagnostic_locks_latches.sql          ← Community MySQL 8.0/8.4
│   ├── enable_instrumentation.sql                  ← Enable full performance_schema instrumentation
│   └── generate_html_report.sh                     ← Colourful HTML report with recommendations
│
├── tests/                                          ← Stress test & simulation scripts
│   ├── aurora_test_setup.sql                       ← Creates test schema + 1.2M rows
│   ├── aurora_parallel_test.sh                     ← Parallel query test with metrics
│   └── aurora_lock_contention_test.sh              ← 5-scenario lock contention simulator
│
├── scheduling/                                     ← Automation & scheduling guides
│   ├── linux_cron_setup.sh                         ← Interactive cron installer script
│   ├── linux_systemd_timer.md                      ← Systemd timer setup guide
│   └── windows_task_scheduler.md                   ← Windows Task Scheduler guide
│
├── sample-reports/                                 ← Example outputs from real test runs
│   ├── SAMPLE_report.html                          ← HTML report (open in browser)
│   ├── SAMPLE_dynamic_recommendations.txt          ← Auto-generated recommendations
│   ├── SAMPLE_parallel_query_report.txt            ← Parallel test summary
│   ├── SAMPLE_lock_contention_report.txt           ← Lock contention test summary
│   ├── SAMPLE_live_lock_diagnostics.txt            ← Live lock capture (blocking chains)
│   └── SAMPLE_diagnostic_output.txt                ← Full diagnostic script output
│
├── README.md
└── .gitignore
```

---

## Diagnostic Scripts: Which One Do I Use?

This toolkit includes **two versions** of the diagnostic script, each tailored to a specific MySQL environment:

<table>
<tr>
<th width="50%">

### <img src="https://img.shields.io/badge/-Aurora_MySQL-527FFF?style=flat-square&logo=amazon-aws&logoColor=white"/> diagnostics/aurora_mysql_diagnostic_locks_latches.sql

</th>
<th width="50%">

### <img src="https://img.shields.io/badge/-Community_MySQL-4479A1?style=flat-square&logo=mysql&logoColor=white"/> diagnostics/mysql_diagnostic_locks_latches.sql

</th>
</tr>
<tr>
<td>

**Target:** Amazon Aurora MySQL 3.x

**Use when:** Running on Aurora RDS

**Aurora-specific features included:**
- `Aurora_lockmgr_memory_used`
- `aurora_lock_thread_slot_futex` wait events
- `io/aurora_redo_log_flush` storage latency
- `Aurora_fwd_*` write forwarding metrics
- `Aurora_pq_*` parallel query stats
- `information_schema.replica_host_status`
- Aurora thread pool metrics

**Removed (not applicable to Aurora):**
- `@@innodb_io_capacity` / `@@innodb_io_capacity_max`
- `@@innodb_log_buffer_size`
- `@@innodb_buffer_pool_instances`
- `@@innodb_change_buffering`
- `@@innodb_write_io_threads`
- `@@innodb_page_cleaners`
- `@@tx_isolation` (removed in Aurora 3)
- Buffer pool dirty page counters

</td>
<td>

**Target:** Community MySQL 8.0 / 8.4

**Use when:** Running on self-hosted MySQL, EC2 MySQL, or on-prem

**Standard MySQL features included:**
- All `@@innodb_*` variables
- Local I/O capacity metrics
- Redo log buffer configuration
- Buffer pool instances & dirty pages
- Page cleaner threads
- Change buffering status
- `@@tx_isolation` (deprecated but present)

**Will FAIL on Aurora because:**
- References variables Aurora doesn't have
- Uses `\G` formatting (batch-mode incompatible)
- Queries columns not in Aurora's `INNODB_BUFFER_POOL_STATS`

</td>
</tr>
<tr>
<td>

```bash
# Run on Aurora
export MYSQL_PWD='password'
mysql -h cluster.xxx.rds.amazonaws.com \
  -u admin mydb \
  < diagnostics/aurora_mysql_diagnostic_locks_latches.sql \
  > output.txt 2>&1
```

</td>
<td>

```bash
# Run on Community MySQL
mysql -u root -p mydb \
  < diagnostics/mysql_diagnostic_locks_latches.sql \
  > output.txt 2>&1
```

</td>
</tr>
</table>

> **TL;DR:** Use `aurora_*.sql` for Aurora. Use `mysql_*.sql` for self-hosted/community MySQL. They are **not interchangeable**.

---

## When to Use This vs AWS Performance Insights

> **If you're an AWS customer, start with Performance Insights (PI) — it's free and pre-built. Use this toolkit when PI shows you THAT there's a problem but you need to understand WHY.**

<table>
<tr>
<th width="50%">

### <img src="https://img.shields.io/badge/-Performance_Insights-FF9900?style=flat-square&logo=amazon-aws&logoColor=white"/> Use PI When...

</th>
<th width="50%">

### <img src="https://img.shields.io/badge/-This_Toolkit-527FFF?style=flat-square&logo=mysql&logoColor=white"/> Use This When...

</th>
</tr>
<tr>
<td>

- Checking if DB is bottlenecked on locks vs CPU vs I/O
- Finding which SQL contributes most to lock wait load
- Trend analysis ("did contention increase after deployment?")
- After-the-fact investigation ("what happened at 3 AM?")
- Capacity planning (AAS vs vCPU count)
- Non-DBA teams need visibility (console UI, no SQL needed)

</td>
<td>

- Application is hung NOW — need exact blocking chain to kill the right session
- Deadlocks spiking — need the exact cycle to fix application logic
- Suspect gap locks — need `LOCK_MODE` detail (GAP vs REC_NOT_GAP vs INSERT_INTENTION)
- ALTER TABLE is hanging — need to find who holds the metadata lock
- Need to know which specific rows are hot (`LOCK_DATA`)
- Want automated recommendations with remediation steps

</td>
</tr>
</table>

### What Performance Insights CANNOT show you:

| Information needed | PI | This toolkit |
|-------------------|:--:|:------------:|
| Exact blocking chain (PID 42 blocks PID 78) | No | **Yes** |
| Specific locked row (primary key value) | No | **Yes** |
| Gap lock vs record lock vs next-key lock | No | **Yes** |
| Deadlock cycle details (both transactions + locks) | No | **Yes** |
| Metadata lock holders (who blocks DDL) | No | **Yes** |
| INSERT_INTENTION lock waits | No | **Yes** |
| `sys.innodb_lock_waits` (formatted kill commands) | No | **Yes** |
| Severity-rated remediation recommendations | No | **Yes** |
| Point-in-time snapshot of ALL current locks | No | **Yes** |
| Historical load trend over days/weeks | **Yes** | No |
| AAS by wait type (time-series graph) | **Yes** | No |
| Top SQL by database load | **Yes** | No |
| CloudWatch alarm integration | **Yes** | No |

### Recommended Workflow (Use Both Together)

```
1. PI alerts (CloudWatch alarm on DBLoadNonCPU) → lock contention detected
2. PI console → identify time window, confirm it's lock waits, find top SQL
3. ⬇️ Pivot to this toolkit ⬇️
4. Run diagnostic script → get blocking chain, lock types, gap locks
5. Read recommendations → identify root cause + fix
6. Remediate (kill blocker, add index, change isolation, fix app logic)
7. PI → confirm load returned to normal post-fix
```

### Performance Insights Pricing

| Tier | Retention | Cost |
|------|-----------|------|
| Free (included with Aurora) | 7 days | $0 |
| Long-term retention | 2 years (731 days) | ~$0.06/vCPU/month |

PI is automatically enabled on Aurora. The free tier is sufficient for most troubleshooting.

---

## Performance Schema Instrumentation (Important!)

> **Without proper instrumentation, mutex/rwlock/cond wait data will be MISSING from your reports.**

Aurora MySQL 3.x has most `wait/synch/*` instruments **DISABLED by default**. You need to enable them for full visibility.

### What's enabled by default?

| Instrument Family | Default | Data you get |
|-------------------|---------|-------------|
| `wait/synch/mutex/*` | **DISABLED** | Mutex contention (lock_sys, trx_sys, etc.) |
| `wait/synch/rwlock/*` | **DISABLED** | Read-write lock contention |
| `wait/synch/cond/*` | **DISABLED** | Condition variable waits (row_lock_wait!) |
| `wait/lock/*` | Enabled | Table/metadata lock waits |
| `wait/io/*` | Enabled | I/O waits (Aurora storage layer) |
| `stage/*` | **DISABLED** | What each thread is doing (stages) |
| `statement/*` | Enabled | Query execution stats |
| `transaction/*` | Enabled | Transaction stats |

| Consumer | Default | What it collects |
|----------|---------|-----------------|
| `events_waits_current` | **DISABLED** | Current wait per thread |
| `events_waits_history` | **DISABLED** | Recent waits per thread |
| `events_stages_current` | **DISABLED** | Current stage per thread |
| `events_statements_current` | Enabled | Current statement per thread |
| `events_transactions_current` | Enabled | Current transaction per thread |

### Quick fix: Enable instrumentation

```bash
# Run the provided enablement script (immediate, no reboot needed)
mysql -h <aurora-endpoint> -u <user> < diagnostics/enable_instrumentation.sql
```

### Persistent fix: Aurora DB parameter group

Add these to your cluster parameter group (requires reboot):

```
performance_schema = 1
performance-schema-instrument = 'wait/%=ON'
performance-schema-consumer-events-waits-current = ON
performance-schema-consumer-events-waits-history = ON
performance-schema-consumer-events-stages-current = ON
performance-schema-consumer-events-stages-history = ON
```

### If using Performance Insights

When Performance Insights manages performance_schema automatically (default), it enables:
- All `wait/%` instruments
- `events_waits_current` consumer

This is sufficient for most diagnostics. The HTML report will warn you if instrumentation is missing.

### Important restrictions

| Constraint | Detail |
|-----------|--------|
| **T-class instances** | Do NOT enable performance_schema on db.t2/t3/t4g — risk of OOM |
| **CPU overhead** | ~5-10% with all wait/synch instruments enabled |
| **Memory** | Auto-sized via `performance_schema_max_*` parameters; monitor with CloudWatch |
| **Reboot required** | Only for enabling `performance_schema` itself; instrument/consumer changes are immediate |

---

## Quick Start

### Prerequisites

- `mysql` CLI client installed
- Network access to your Aurora cluster (or MySQL instance)
- User with `SELECT` on `performance_schema` + `PROCESS` privilege
- `performance_schema = 1` enabled in Aurora parameter group
- For full visibility: run `enable_instrumentation.sql` (see above)

### 1. Clone and Deploy

```bash
git clone https://github.com/<your-username>/aurora-diagnostic.git
cd aurora-diagnostic

# Copy to EC2 (for Aurora)
scp -i "key.pem" -r diagnostics/ tests/ scheduling/ ubuntu@<ec2-host>:~/aurora-diagnostic/
```

### 2. Run Diagnostic (read-only, production-safe)

```bash
export MYSQL_PWD='your_password'
mysql -h <aurora-endpoint> -u <user> <database> \
  < diagnostics/aurora_mysql_diagnostic_locks_latches.sql > diagnostic.txt 2>&1
```

### 3. Set Up Test Data (test environments only)

```bash
mysql -h <aurora-endpoint> -u <user> < tests/aurora_test_setup.sql
```

### 4. Run Parallel Query Test

```bash
# Edit script header to set AURORA_HOST, AURORA_USER, password
bash tests/aurora_parallel_test.sh
```

### 5. Run Lock Contention Simulation

```bash
# Edit script header to set AURORA_HOST, AURORA_USER, password
bash tests/aurora_lock_contention_test.sh
```

### 6. Generate HTML Report (colourful, with recommendations)

```bash
export AURORA_HOST='your-cluster-endpoint'
export AURORA_USER='your-user'
export MYSQL_PWD='your-password'
export AURORA_DB='your-database'
bash diagnostics/generate_html_report.sh

# Opens a dark-themed HTML report with:
# - Colour-coded severity metrics (green/yellow/red)
# - Dynamic recommendations based on actual instance state
# - Instrumentation status warnings
# - Top wait events, blocking pairs, lock-heavy statements
```

---

## Diagnostic Coverage (25 Sections)

<details>
<summary><strong>Click to expand full section list</strong></summary>

| # | Section | What it reveals |
|---|---------|----------------|
| 1 | Aurora Instance Identity | Version, server ID, writer/reader role |
| 2 | InnoDB Lock Diagnostics | Current data_locks, data_lock_waits, blocking pairs |
| 3 | Metadata Locks (MDL) | DDL/DML conflicts, pending MDL waiters |
| 4 | Table Lock Waits | Table-level and index-level I/O wait summaries |
| 5 | Mutex & Latch Diagnostics | InnoDB mutexes, rwlocks, Aurora futex contention |
| 6 | Deadlock Diagnostics | Deadlock count, row lock statistics |
| 7 | Wait Event Analysis | Current and global wait events, per-thread waits |
| 8 | Statement & Stage Analysis | Running queries, lock time, latency variance |
| 9 | Gap Locks & Next-Key Locks | Gap lock detection (critical for parallel issues) |
| 10 | Auto-Increment Locks | `innodb_autoinc_lock_mode`, related waits |
| 11 | InnoDB Configuration | Lock/concurrency parameters (Aurora-safe subset) |
| 12 | Aurora Lock Manager | `Aurora_lockmgr_memory_used`, commit latency, PQ stats |
| 13 | Aurora Redo Log Waits | Storage layer latency, history list length |
| 14 | InnoDB Metrics | Lock, transaction, AHI subsystem counters |
| 15 | Buffer Pool Status | Hit rate, reads, pages (Aurora-relevant fields) |
| 16 | Memory & Temp Tables | Memory consumers, tmp table usage |
| 17 | File I/O | Storage layer I/O by event and instance |
| 18 | Prepared Statements | Lock time per prepared statement |
| 19 | Transaction History | Active transactions, per-thread summary |
| 20 | Error Summary | Lock timeout and deadlock error counts |
| 21 | sys Schema Views | `innodb_lock_waits`, `schema_table_lock_waits`, session |
| 22 | Aurora Replica Lag | Replica lag in milliseconds, CPU per replica |
| 23 | Instrumentation Check | Enabled instruments and consumers |
| 24 | Enable Instruments | Commented SQL to enable disabled instruments |
| 25 | Recommendations | Actionable checklist for parallel query issues |

</details>

---

## Lock Contention Test Scenarios

The contention test (`tests/aurora_lock_contention_test.sh`) simulates real-world parallel DML patterns:

| Scenario | Workers | Lock Type | What Happens |
|:--------:|:-------:|-----------|--------------|
| **1** | 50 | `X` row locks | Concurrent UPDATEs on overlapping `dim_position_id` values |
| **2** | 25 | `X` record locks | SELECT FOR UPDATE competing with UPDATE for same rows |
| **3** | 5 | Wide range `X` locks | Long transactions hold locks for 5-8s, causing cascading waits |
| **4** | 25 | `X,GAP` + `INSERT_INTENTION` | DELETE + INSERT in same range = gap lock deadlocks |
| **5** | 25 | `S` → `X` upgrade | LOCK IN SHARE MODE followed by UPDATE = upgrade deadlocks |

### Sample Results

```
┌────────────────────────────────┬──────────┬──────────┬──────────────────────────────────┐
│ Metric                         │  Before  │  After   │ What it means                    │
├────────────────────────────────┼──────────┼──────────┼──────────────────────────────────┤
│ Innodb_row_lock_waits          │    0     │   146    │ 146 row lock contentions         │
│ Innodb_row_lock_time (ms)      │    0     │ 711,788  │ ~12 min aggregate wait time      │
│ Max single lock wait (ms)      │    0     │  30,368  │ Worst case: 30s blocked          │
│ Deadlocks                      │    0     │    37    │ Circular lock dependencies       │
│ Lock timeouts                  │    0     │     2    │ Exceeded innodb_lock_wait_timeout │
│ Aurora_lockmgr_memory_used     │   5 MB   │  25 MB   │ 5x growth in lock structures     │
└────────────────────────────────┴──────────┴──────────┴──────────────────────────────────┘
```

---

## Scheduling & Automation

<table>
<tr>
<th width="33%">

### <img src="https://img.shields.io/badge/-Linux_Cron-FCC624?style=flat-square&logo=linux&logoColor=black"/> Cron

</th>
<th width="33%">

### <img src="https://img.shields.io/badge/-Linux_Systemd-333?style=flat-square&logo=linux&logoColor=white"/> Systemd Timer

</th>
<th width="33%">

### <img src="https://img.shields.io/badge/-Windows-0078D6?style=flat-square&logo=windows&logoColor=white"/> Task Scheduler

</th>
</tr>
<tr>
<td>

Simple, universally available.

```bash
# Interactive setup
chmod +x scheduling/linux_cron_setup.sh
./scheduling/linux_cron_setup.sh
```

Or manually:
```bash
crontab -e
```
```cron
# Every 15 minutes
*/15 * * * * ~/aurora-diagnostic/scheduling/run_diagnostic.sh
```

</td>
<td>

Better logging, missed-run recovery, resource limits.

See [`scheduling/linux_systemd_timer.md`](scheduling/linux_systemd_timer.md)

```bash
sudo systemctl enable aurora-diagnostic.timer
sudo systemctl start aurora-diagnostic.timer
```

</td>
<td>

GUI or PowerShell.

See [`scheduling/windows_task_scheduler.md`](scheduling/windows_task_scheduler.md)

```powershell
# PowerShell one-liner
schtasks /create /tn "Aurora Diagnostic" `
  /tr "powershell -File C:\aurora-diagnostic\run_diagnostic.ps1" `
  /sc minute /mo 15
```

</td>
</tr>
</table>

### Scheduling Quick Reference

| Schedule | Cron Expression | When to Use |
|----------|----------------|-------------|
| Every 5 minutes | `*/5 * * * *` | Active incident troubleshooting |
| Every 15 minutes | `*/15 * * * *` | Regular monitoring |
| Every hour | `0 * * * *` | Baseline collection |
| Business hours only | `*/15 8-20 * * 1-5` | Weekday monitoring (UTC) |
| Daily at 2 AM | `0 2 * * *` | Nightly comprehensive capture |
| Weekly (Sunday 3 AM) | `0 3 * * 0` | Stress test scheduling |

---

## Dynamic Recommendations Engine (Section 25)

The diagnostic script doesn't just collect data — it **analyzes the current state and outputs actionable recommendations** with severity levels:

```
--- DEADLOCK ANALYSIS ---
  [CRITICAL] 81 deadlocks detected. Immediate action required.
  REMEDIATION: (1) Run SHOW ENGINE INNODB STATUS... (2) Ensure same access order...

--- ROW LOCK CONTENTION ANALYSIS ---
  [CRITICAL] 324 row lock waits. Heavy contention.
  Average wait: 4552ms | Max wait: 30368ms
  REMEDIATION: (1) Check data_lock_waits... (2) Identify hot rows...

--- GAP LOCK ANALYSIS ---
  [WARNING] 29 gap locks detected. Current isolation: REPEATABLE-READ
  REMEDIATION: (1) Switch to READ-COMMITTED... (2) Use exact-match WHERE...

--- OVERALL ASSESSMENT ---
  Deadlocks: 81 | Row lock waits: 324 | Lock timeouts: 3 | Active trx: 74 | Max trx age: 45s
```

**Checks performed automatically:**

| Check | Severity Thresholds | Remediation Provided |
|-------|---------------------|---------------------|
| Deadlocks | >50 CRITICAL, >10 WARNING | Access order, indexes, isolation level |
| Row lock waits | >100 CRITICAL, >20 WARNING | Blocking pair ID, hot row detection |
| Gap locks | >10 CRITICAL, >0 WARNING | Isolation switch, WHERE clause tuning |
| Long transactions | >60s CRITICAL, >30s WARNING | Batch splitting, timeout tuning |
| Lock wait timeouts | >10 CRITICAL, >0 WARNING | Root cause, retry logic |
| Metadata locks | Any pending = WARNING | DDL scheduling, pt-osc |
| Connection saturation | >90% CRITICAL, >70% WARNING | Pooling, max_connections |
| Purge lag | >100K CRITICAL, >10K WARNING | Long-read termination, reader offload |
| Auto-increment mode | Mode 0 = CRITICAL | Switch to mode 2 |

---

## Interpreting Results

### Red Flags in Diagnostic Output

| Signal | Where to look | Indicates |
|--------|--------------|-----------|
| `Innodb_row_lock_current_waits > 0` | Section 6 | Active lock contention right now |
| `LOCK_STATUS = 'WAITING'` in `data_locks` | Section 2 | Transactions blocked on row locks |
| `X,GAP,INSERT_INTENTION` in WAITING | Section 9 | Gap lock deadlock pattern |
| `lock_deadlocks` count growing | Section 6 | Circular lock dependencies |
| `Aurora_lockmgr_memory_used` spiking | Section 12 | Many lock structures held |
| `wait/synch/cond/innodb/row_lock_wait` high | Section 7 | Threads sleeping on row locks |
| Latency variance (max >> min) | Section 8 | Contention causing unpredictable perf |

### Common Root Causes

| Cause | Fix |
|-------|-----|
| Gap locks under REPEATABLE-READ | Switch to `READ-COMMITTED` isolation |
| Missing indexes | Add covering index to reduce lock footprint |
| Long-running transactions | Reduce transaction scope, add timeouts |
| Auto-increment contention | Set `innodb_autoinc_lock_mode = 2` |
| Shared-to-exclusive lock upgrades | Avoid `LOCK IN SHARE MODE` before UPDATE |
| Wide range scans with FOR UPDATE | Use narrower WHERE clauses, add indexes |

---

## Sample Reports

The [`sample-reports/`](sample-reports/) directory contains real outputs from test runs on Aurora MySQL 3.11.1, so you can see exactly what to expect:

| File | Shows |
|------|-------|
| [`SAMPLE_parallel_query_report.txt`](sample-reports/SAMPLE_parallel_query_report.txt) | Parallel test: individual vs 100 concurrent queries, latency stats |
| [`SAMPLE_lock_contention_report.txt`](sample-reports/SAMPLE_lock_contention_report.txt) | Lock test: per-scenario results, pre/post metrics, deadlock counts |
| [`SAMPLE_live_lock_diagnostics.txt`](sample-reports/SAMPLE_live_lock_diagnostics.txt) | Live capture: blocking chains, gap locks, wait events during contention |
| [`SAMPLE_diagnostic_output.txt`](sample-reports/SAMPLE_diagnostic_output.txt) | Full diagnostic: all 25 sections with Aurora-specific metrics |
| [`SAMPLE_dynamic_recommendations.txt`](sample-reports/SAMPLE_dynamic_recommendations.txt) | **Auto-generated recommendations** with severity and remediation steps |

---

## Security Notes

> **🟢 Diagnostic scripts are read-only** (SELECT/SHOW only) — safe for production use.

> **🔴 Test scripts modify data** (INSERT/UPDATE/DELETE) — use on test environments only.

For credential management (in order of preference):

| Method | Platform | Security Level | Notes |
|--------|----------|----------------|-------|
| IAM Database Authentication | Aurora | **Recommended** | No passwords — uses IAM roles/tokens |
| AWS Secrets Manager | Any | **Recommended** | Rotatable, auditable, no plaintext |
| `~/.my.cnf` (chmod 600) | Linux | Acceptable | File-system ACL protected |
| Windows Credential Manager | Windows | Acceptable | OS-level encrypted store |
| `MYSQL_PWD` env var | Linux/Windows | **Use with caution** | Deprecated by MySQL. Visible in `/proc/<pid>/environ` to root. Use only for ad-hoc runs, never in automation. |
| `-p` on command line | Any | **Never use** | Visible in `ps` output to all users |

> **AWS Best Practice:** For scheduled/automated runs, use IAM database authentication with an EC2 instance role,
> or retrieve credentials from Secrets Manager at runtime. Never store credentials in scripts or version control.

---

## License

MIT

---

<p align="center">
  <img src="https://img.shields.io/badge/Built_for-DBA_Troubleshooting-FF6B35?style=for-the-badge" alt="Built for DBAs"/>
  <img src="https://img.shields.io/badge/Tested_on-Aurora_3.11.1-527FFF?style=for-the-badge" alt="Tested on Aurora 3.11.1"/>
  <img src="https://img.shields.io/badge/Verified-1.2M_Rows_|_100_Parallel_Sessions-4479A1?style=for-the-badge" alt="Verified"/>
</p>
