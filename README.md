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
│   ├── aurora_mysql_diagnostic_locks_latches.sql   ← Aurora MySQL 3.x (25 sections)
│   └── mysql_diagnostic_locks_latches.sql          ← Community MySQL 8.0/8.4
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

## Quick Start

### Prerequisites

- `mysql` CLI client installed
- Network access to your Aurora cluster (or MySQL instance)
- User with `SELECT` on `performance_schema` + `PROCESS` privilege
- `performance_schema = 1` enabled in Aurora parameter group

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

## Security Notes

> **🟢 Diagnostic scripts are read-only** (SELECT/SHOW only) — safe for production use.

> **🔴 Test scripts modify data** (INSERT/UPDATE/DELETE) — use on test environments only.

For credential management:

| Method | Platform | Security Level |
|--------|----------|----------------|
| `MYSQL_PWD` env var | Linux/Windows | Basic (not in `ps` output) |
| `~/.my.cnf` (chmod 600) | Linux | Good |
| Windows Credential Manager | Windows | Good |
| AWS Secrets Manager | Any | Best |
| IAM Database Authentication | Aurora | Best |

---

## License

MIT

---

<p align="center">
  <img src="https://img.shields.io/badge/Built_for-DBA_Troubleshooting-FF6B35?style=for-the-badge" alt="Built for DBAs"/>
  <img src="https://img.shields.io/badge/Tested_on-Aurora_3.11.1-527FFF?style=for-the-badge" alt="Tested on Aurora 3.11.1"/>
  <img src="https://img.shields.io/badge/Verified-1.2M_Rows_|_100_Parallel_Sessions-4479A1?style=for-the-badge" alt="Verified"/>
</p>
