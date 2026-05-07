#!/bin/bash
# ============================================================================
# Aurora MySQL Diagnostic - HTML Report Generator
# Runs the diagnostic and produces a colourful HTML report with recommendations
# ============================================================================
# Usage:
#   export AURORA_HOST='your-cluster-endpoint'
#   export AURORA_USER='your-user'
#   export MYSQL_PWD='your-password'
#   export AURORA_DB='your-database'
#   bash generate_html_report.sh
# ============================================================================

AURORA_HOST="${AURORA_HOST:-your-cluster.cluster-xxxxx.region.rds.amazonaws.com}"
AURORA_USER="${AURORA_USER:-admin}"
DB="${AURORA_DB:-qldwh}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/aurora_html_reports}"
REPORT_FILE="$OUTPUT_DIR/aurora_diagnostic_${TIMESTAMP}.html"

if [ -z "$MYSQL_PWD" ]; then
    if [ -f "$HOME/.my.cnf" ]; then
        echo "[Info] Using credentials from ~/.my.cnf"
    else
        echo "[ERROR] No credentials found. Set MYSQL_PWD or create ~/.my.cnf"
        echo "Usage:"
        echo "  export AURORA_HOST='your-cluster-endpoint'"
        echo "  export AURORA_USER='your-user'"
        echo "  export MYSQL_PWD='your-password'"
        echo "  export AURORA_DB='your-database'"
        echo "  bash $0"
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR"

MYSQL_CMD="mysql -h $AURORA_HOST -u $AURORA_USER $DB"

echo "[*] Running Aurora MySQL diagnostic with HTML output..."
echo "[*] Target: $AURORA_HOST"
echo "[*] Report: $REPORT_FILE"
echo ""

# ============================================================================
# Collect all diagnostic data as tab-separated values
# ============================================================================

collect_data() {
    $MYSQL_CMD --batch --raw -e "$1" 2>/dev/null
}

# ============================================================================
# Generate HTML Report
# ============================================================================

cat > "$REPORT_FILE" << 'HTML_HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Aurora MySQL Diagnostic Report</title>
<style>
:root {
    --bg: #0f1419;
    --card-bg: #1a2332;
    --card-border: #2d3748;
    --text: #e2e8f0;
    --text-dim: #a0aec0;
    --accent: #527fff;
    --green: #48bb78;
    --yellow: #ecc94b;
    --orange: #ed8936;
    --red: #fc8181;
    --critical-bg: #2d1b1b;
    --warning-bg: #2d2a1b;
    --ok-bg: #1b2d1f;
    --info-bg: #1b2130;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', monospace;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
    padding: 2rem;
}
.container { max-width: 1400px; margin: 0 auto; }
header {
    text-align: center;
    margin-bottom: 3rem;
    padding: 2rem;
    background: linear-gradient(135deg, #1a2332 0%, #0f1925 100%);
    border-radius: 16px;
    border: 1px solid var(--card-border);
}
header h1 {
    font-size: 2rem;
    background: linear-gradient(90deg, var(--accent), #a78bfa);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    margin-bottom: 0.5rem;
}
header .subtitle { color: var(--text-dim); font-size: 0.9rem; }
.badges { display: flex; gap: 1rem; justify-content: center; margin-top: 1rem; flex-wrap: wrap; }
.badge {
    padding: 0.3rem 0.8rem;
    border-radius: 20px;
    font-size: 0.75rem;
    font-weight: 600;
}
.badge-aurora { background: #527fff33; color: var(--accent); border: 1px solid var(--accent); }
.badge-version { background: #48bb7833; color: var(--green); border: 1px solid var(--green); }
.badge-time { background: #a78bfa33; color: #a78bfa; border: 1px solid #a78bfa; }
.section {
    margin-bottom: 2rem;
    background: var(--card-bg);
    border-radius: 12px;
    border: 1px solid var(--card-border);
    overflow: hidden;
}
.section-header {
    padding: 1rem 1.5rem;
    background: linear-gradient(90deg, #1e293b, #1a2332);
    border-bottom: 1px solid var(--card-border);
    font-size: 1rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    gap: 0.5rem;
}
.section-body { padding: 1.5rem; }
table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8rem;
}
th {
    text-align: left;
    padding: 0.6rem 0.8rem;
    background: #2d3748;
    color: var(--accent);
    font-weight: 600;
    border-bottom: 2px solid var(--accent);
    white-space: nowrap;
}
td {
    padding: 0.5rem 0.8rem;
    border-bottom: 1px solid #2d374855;
    word-break: break-word;
}
tr:hover td { background: #2d374833; }
.severity-critical {
    background: var(--critical-bg);
    border-left: 4px solid var(--red);
    padding: 1rem 1.5rem;
    margin: 0.5rem 0;
    border-radius: 8px;
}
.severity-warning {
    background: var(--warning-bg);
    border-left: 4px solid var(--yellow);
    padding: 1rem 1.5rem;
    margin: 0.5rem 0;
    border-radius: 8px;
}
.severity-ok {
    background: var(--ok-bg);
    border-left: 4px solid var(--green);
    padding: 1rem 1.5rem;
    margin: 0.5rem 0;
    border-radius: 8px;
}
.severity-info {
    background: var(--info-bg);
    border-left: 4px solid var(--accent);
    padding: 1rem 1.5rem;
    margin: 0.5rem 0;
    border-radius: 8px;
}
.severity-label {
    font-weight: 700;
    font-size: 0.75rem;
    text-transform: uppercase;
    margin-bottom: 0.3rem;
}
.severity-critical .severity-label { color: var(--red); }
.severity-warning .severity-label { color: var(--yellow); }
.severity-ok .severity-label { color: var(--green); }
.severity-info .severity-label { color: var(--accent); }
.remediation {
    margin-top: 0.8rem;
    padding: 0.8rem 1rem;
    background: #0f141966;
    border-radius: 6px;
    font-size: 0.8rem;
    color: var(--text-dim);
}
.remediation strong { color: var(--orange); }
.metric-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
}
.metric-card {
    padding: 1rem;
    background: #0f1419;
    border-radius: 8px;
    border: 1px solid var(--card-border);
    text-align: center;
}
.metric-value {
    font-size: 1.8rem;
    font-weight: 700;
    margin: 0.3rem 0;
}
.metric-label { font-size: 0.7rem; color: var(--text-dim); text-transform: uppercase; }
.metric-value.critical { color: var(--red); }
.metric-value.warning { color: var(--yellow); }
.metric-value.ok { color: var(--green); }
.summary-bar {
    padding: 1rem 1.5rem;
    background: linear-gradient(90deg, #1e293b, #2d3748);
    border-radius: 8px;
    margin-bottom: 2rem;
    font-size: 0.85rem;
    display: flex;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.5rem;
}
.collapsible { cursor: pointer; }
.collapsible-content { display: none; }
.collapsible-content.show { display: block; }
.toggle-icon { float: right; color: var(--text-dim); }
pre {
    background: #0f1419;
    padding: 1rem;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 0.75rem;
    border: 1px solid var(--card-border);
}
.instrumentation-note {
    background: #2d2a1b;
    border: 1px solid #ecc94b55;
    border-radius: 8px;
    padding: 1rem 1.5rem;
    margin-bottom: 2rem;
    font-size: 0.85rem;
}
.instrumentation-note strong { color: var(--yellow); }
footer {
    text-align: center;
    margin-top: 3rem;
    padding: 1.5rem;
    color: var(--text-dim);
    font-size: 0.75rem;
    border-top: 1px solid var(--card-border);
}
</style>
</head>
<body>
<div class="container">
HTML_HEADER

# ============================================================================
# Instance Info
# ============================================================================
INSTANCE_INFO=$(collect_data "SELECT VERSION() AS v, @@aurora_version AS av, @@aurora_server_id AS sid, @@hostname AS h, @@innodb_read_only AS ro;")
MYSQL_VER=$(echo "$INSTANCE_INFO" | tail -1 | cut -f1)
AURORA_VER=$(echo "$INSTANCE_INFO" | tail -1 | cut -f2)
SERVER_ID=$(echo "$INSTANCE_INFO" | tail -1 | cut -f3)
IS_READER=$(echo "$INSTANCE_INFO" | tail -1 | cut -f5)

ROLE="Writer"
[ "$IS_READER" = "1" ] && ROLE="Reader"

cat >> "$REPORT_FILE" << HTML
<header>
    <h1>Aurora MySQL Diagnostic Report</h1>
    <p class="subtitle">Lock Contention, Deadlocks &amp; Performance Schema Analysis</p>
    <div class="badges">
        <span class="badge badge-aurora">Aurora MySQL $AURORA_VER</span>
        <span class="badge badge-version">MySQL $MYSQL_VER | $ROLE Instance</span>
        <span class="badge badge-time">$(date '+%Y-%m-%d %H:%M:%S %Z')</span>
    </div>
</header>
HTML

# ============================================================================
# Performance Schema Instrumentation Check
# ============================================================================
DISABLED_CONSUMERS=$(collect_data "SELECT NAME FROM performance_schema.setup_consumers WHERE ENABLED = 'NO' AND NAME LIKE 'events_%';")
DISABLED_WAIT_INSTR=$(collect_data "SELECT COUNT(*) FROM performance_schema.setup_instruments WHERE NAME LIKE 'wait/synch/%' AND ENABLED = 'NO';")
DISABLED_WAIT_COUNT=$(echo "$DISABLED_WAIT_INSTR" | tail -1)

cat >> "$REPORT_FILE" << HTML
<div class="instrumentation-note">
    <strong>⚠ Performance Schema Instrumentation Status</strong><br>
HTML

if [ "$DISABLED_WAIT_COUNT" -gt 0 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <p style="margin-top:0.5rem"><span style="color:var(--yellow)">$DISABLED_WAIT_COUNT wait/synch instruments are DISABLED.</span>
    Some mutex/rwlock/cond wait data may be missing from this report.</p>
    <p style="margin-top:0.5rem; color:var(--text-dim)">To enable full instrumentation, run:</p>
    <pre>UPDATE performance_schema.setup_instruments SET ENABLED='YES', TIMED='YES' WHERE NAME LIKE 'wait/synch/%';
UPDATE performance_schema.setup_instruments SET ENABLED='YES', TIMED='YES' WHERE NAME LIKE 'wait/lock/%';
UPDATE performance_schema.setup_consumers SET ENABLED='YES' WHERE NAME LIKE 'events_waits%';
UPDATE performance_schema.setup_consumers SET ENABLED='YES' WHERE NAME LIKE 'events_stages%';
UPDATE performance_schema.setup_consumers SET ENABLED='YES' WHERE NAME LIKE 'events_transactions%';</pre>
    <p style="margin-top:0.5rem; color:var(--text-dim)">Or set in your Aurora DB parameter group for persistence across restarts:
    <code>performance_schema_instrument = 'wait/synch/%=ON'</code></p>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <p style="margin-top:0.5rem; color:var(--green)">✓ All wait/synch instruments are enabled. Full diagnostic data available.</p>
HTML
fi

# Check consumers
DISABLED_CONSUMER_LIST=$(collect_data "SELECT GROUP_CONCAT(NAME SEPARATOR ', ') FROM performance_schema.setup_consumers WHERE ENABLED = 'NO' AND NAME LIKE 'events_%';")
DISABLED_CON_VAL=$(echo "$DISABLED_CONSUMER_LIST" | tail -1)
if [ -n "$DISABLED_CON_VAL" ] && [ "$DISABLED_CON_VAL" != "NULL" ]; then
    cat >> "$REPORT_FILE" << HTML
    <p style="margin-top:0.5rem"><span style="color:var(--orange)">Disabled consumers:</span> <code style="font-size:0.75rem">$DISABLED_CON_VAL</code></p>
HTML
fi

echo "</div>" >> "$REPORT_FILE"

# ============================================================================
# Key Metrics Summary
# ============================================================================
METRICS=$(collect_data "
SELECT
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_deadlocks') AS deadlocks,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_waits') AS lock_waits,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time_max') AS max_wait_ms,
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_timeouts') AS timeouts,
    (SELECT COUNT(*) FROM information_schema.INNODB_TRX) AS active_trx,
    (SELECT COALESCE(MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())), 0) FROM information_schema.INNODB_TRX) AS max_trx_age,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') AS threads,
    @@max_connections AS max_conn,
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len') AS hist_len,
    (SELECT COUNT(*) FROM performance_schema.data_locks WHERE LOCK_MODE LIKE '%GAP%') AS gap_locks,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_current_waits') AS current_waits;
")

DEADLOCKS=$(echo "$METRICS" | tail -1 | cut -f1)
LOCK_WAITS=$(echo "$METRICS" | tail -1 | cut -f2)
MAX_WAIT=$(echo "$METRICS" | tail -1 | cut -f3)
TIMEOUTS=$(echo "$METRICS" | tail -1 | cut -f4)
ACTIVE_TRX=$(echo "$METRICS" | tail -1 | cut -f5)
MAX_TRX_AGE=$(echo "$METRICS" | tail -1 | cut -f6)
THREADS=$(echo "$METRICS" | tail -1 | cut -f7)
MAX_CONN=$(echo "$METRICS" | tail -1 | cut -f8)
HIST_LEN=$(echo "$METRICS" | tail -1 | cut -f9)
GAP_LOCKS=$(echo "$METRICS" | tail -1 | cut -f10)
CURRENT_WAITS=$(echo "$METRICS" | tail -1 | cut -f11)

# Determine severity classes
dl_class="ok"; [ "$DEADLOCKS" -gt 10 ] 2>/dev/null && dl_class="warning"; [ "$DEADLOCKS" -gt 50 ] 2>/dev/null && dl_class="critical"
lw_class="ok"; [ "$LOCK_WAITS" -gt 20 ] 2>/dev/null && lw_class="warning"; [ "$LOCK_WAITS" -gt 100 ] 2>/dev/null && lw_class="critical"
to_class="ok"; [ "$TIMEOUTS" -gt 0 ] 2>/dev/null && to_class="warning"; [ "$TIMEOUTS" -gt 10 ] 2>/dev/null && to_class="critical"
ta_class="ok"; [ "$MAX_TRX_AGE" -gt 30 ] 2>/dev/null && ta_class="warning"; [ "$MAX_TRX_AGE" -gt 60 ] 2>/dev/null && ta_class="critical"
gl_class="ok"; [ "$GAP_LOCKS" -gt 0 ] 2>/dev/null && gl_class="warning"; [ "$GAP_LOCKS" -gt 10 ] 2>/dev/null && gl_class="critical"
cw_class="ok"; [ "$CURRENT_WAITS" -gt 0 ] 2>/dev/null && cw_class="warning"; [ "$CURRENT_WAITS" -gt 10 ] 2>/dev/null && cw_class="critical"

cat >> "$REPORT_FILE" << HTML
<div class="section">
    <div class="section-header">📊 Instance Health Summary</div>
    <div class="section-body">
        <div class="metric-grid">
            <div class="metric-card">
                <div class="metric-label">Deadlocks</div>
                <div class="metric-value $dl_class">$DEADLOCKS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Row Lock Waits</div>
                <div class="metric-value $lw_class">$LOCK_WAITS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Current Waits</div>
                <div class="metric-value $cw_class">$CURRENT_WAITS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Max Wait (ms)</div>
                <div class="metric-value $lw_class">$MAX_WAIT</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Lock Timeouts</div>
                <div class="metric-value $to_class">$TIMEOUTS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Gap Locks</div>
                <div class="metric-value $gl_class">$GAP_LOCKS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Active Transactions</div>
                <div class="metric-value ok">$ACTIVE_TRX</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Longest Trx (sec)</div>
                <div class="metric-value $ta_class">$MAX_TRX_AGE</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Connections</div>
                <div class="metric-value ok">$THREADS / $MAX_CONN</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">History List</div>
                <div class="metric-value ok">$HIST_LEN</div>
            </div>
        </div>
    </div>
</div>
HTML

# ============================================================================
# Recommendations Section
# ============================================================================
cat >> "$REPORT_FILE" << 'HTML'
<div class="section">
    <div class="section-header">🔍 Dynamic Recommendations</div>
    <div class="section-body">
HTML

# Deadlock recommendation
if [ "$DEADLOCKS" -gt 50 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-critical">
        <div class="severity-label">CRITICAL — Deadlocks: $DEADLOCKS</div>
        <p>High deadlock rate indicates circular lock dependencies between concurrent transactions.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Run <code>SHOW ENGINE INNODB STATUS</code> → check LATEST DETECTED DEADLOCK for the exact cycle<br>
            2. Ensure all transactions access tables and rows in the <strong>same order</strong><br>
            3. Keep transactions short — commit after each logical unit of work<br>
            4. Add indexes to reduce the number of rows locked per statement<br>
            5. Switch to <code>READ-COMMITTED</code> isolation to eliminate gap locks<br>
            6. Implement application retry logic for <code>ER_LOCK_DEADLOCK</code> (error 1213)
        </div>
    </div>
HTML
elif [ "$DEADLOCKS" -gt 10 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-warning">
        <div class="severity-label">WARNING — Deadlocks: $DEADLOCKS</div>
        <p>Moderate deadlock rate. Investigate blocking patterns before they escalate.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Check SHOW ENGINE INNODB STATUS for deadlock details<br>
            2. Review transaction access order consistency<br>
            3. Consider adding indexes on frequently locked columns
        </div>
    </div>
HTML
elif [ "$DEADLOCKS" -gt 0 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-info">
        <div class="severity-label">INFO — Deadlocks: $DEADLOCKS</div>
        <p>Low deadlock count. Monitor for increase during peak load.</p>
    </div>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-ok">
        <div class="severity-label">OK — No Deadlocks</div>
        <p>No deadlocks detected since last counter reset.</p>
    </div>
HTML
fi

# Row lock contention
if [ "$LOCK_WAITS" -gt 100 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-critical">
        <div class="severity-label">CRITICAL — Row Lock Waits: $LOCK_WAITS (Max: ${MAX_WAIT}ms)</div>
        <p>Heavy row lock contention. Parallel queries are blocking each other.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Check <code>performance_schema.data_lock_waits</code> to identify blocking transaction pairs<br>
            2. Identify hot rows/indexes being contended (look at LOCK_DATA values)<br>
            3. Reduce transaction duration — don't hold locks while doing application processing<br>
            4. Add covering indexes to reduce the number of rows examined/locked<br>
            5. Use optimistic locking patterns with retry on conflict<br>
            6. For read-heavy workloads, use <code>SELECT ... WITH (NOLOCK)</code> or read from Aurora reader instance
        </div>
    </div>
HTML
elif [ "$LOCK_WAITS" -gt 20 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-warning">
        <div class="severity-label">WARNING — Row Lock Waits: $LOCK_WAITS (Max: ${MAX_WAIT}ms)</div>
        <p>Moderate lock contention detected. May degrade under increased parallel load.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Review data_lock_waits for blocking pairs<br>
            2. Check if indexes can reduce lock scope<br>
            3. Consider shorter transaction boundaries
        </div>
    </div>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-ok">
        <div class="severity-label">OK — Row Lock Waits: $LOCK_WAITS</div>
        <p>Low or no row lock contention.</p>
    </div>
HTML
fi

# Gap locks
ISO_LEVEL=$(collect_data "SELECT @@transaction_isolation;" | tail -1)
if [ "$GAP_LOCKS" -gt 10 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-critical">
        <div class="severity-label">CRITICAL — Gap Locks: $GAP_LOCKS (Isolation: $ISO_LEVEL)</div>
        <p>Gap locks prevent concurrent INSERTs into locked ranges. Major cause of deadlocks in parallel INSERT/DELETE workloads.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Switch to <code>READ-COMMITTED</code> via DB parameter group (⚠️ affects ALL new sessions cluster-wide; test in non-prod first)<br>
            2. This eliminates gap locks for non-locking reads and most DML<br>
            3. Use unique/exact-match WHERE clauses instead of range scans<br>
            4. Avoid DELETE + INSERT patterns — use <code>INSERT ON DUPLICATE KEY UPDATE</code><br>
            5. Ensure <code>innodb_autoinc_lock_mode=2</code> for parallel inserts
        </div>
    </div>
HTML
elif [ "$GAP_LOCKS" -gt 0 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-warning">
        <div class="severity-label">WARNING — Gap Locks: $GAP_LOCKS (Isolation: $ISO_LEVEL)</div>
        <p>Gap locks detected. May block parallel INSERTs into the same index range.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Consider <code>READ-COMMITTED</code> isolation if gap locks cause INSERT contention<br>
            2. Use narrower WHERE clauses to reduce gap lock range
        </div>
    </div>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-ok">
        <div class="severity-label">OK — No Gap Locks (Isolation: $ISO_LEVEL)</div>
        <p>No gap locks detected at this moment.</p>
    </div>
HTML
fi

# Long transactions
if [ "$MAX_TRX_AGE" -gt 60 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-critical">
        <div class="severity-label">CRITICAL — Longest Transaction: ${MAX_TRX_AGE}s ($ACTIVE_TRX active)</div>
        <p>Long-running transactions hold locks and prevent other sessions from proceeding.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Identify the long transaction from <code>information_schema.INNODB_TRX</code><br>
            2. Break large operations into smaller batches (e.g., UPDATE 1000 rows at a time)<br>
            3. Avoid <code>SELECT ... FOR UPDATE</code> on large result sets<br>
            4. Set <code>innodb_lock_wait_timeout</code> lower (e.g., 10s) so blocked sessions fail fast<br>
            5. Move long analytical queries to a reader instance
        </div>
    </div>
HTML
elif [ "$MAX_TRX_AGE" -gt 30 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-warning">
        <div class="severity-label">WARNING — Longest Transaction: ${MAX_TRX_AGE}s ($ACTIVE_TRX active)</div>
        <p>Moderately long transaction. May cause lock accumulation under parallel load.</p>
        <div class="remediation">
            <strong>Remediation:</strong> Review transaction boundaries. Commit more frequently.
        </div>
    </div>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-ok">
        <div class="severity-label">OK — No Long Transactions (max: ${MAX_TRX_AGE}s, $ACTIVE_TRX active)</div>
        <p>All transactions are running within acceptable duration.</p>
    </div>
HTML
fi

# Lock wait timeouts
if [ "$TIMEOUTS" -gt 0 ] 2>/dev/null; then
    TIMEOUT_VAL=$(collect_data "SELECT @@innodb_lock_wait_timeout;" | tail -1)
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-warning">
        <div class="severity-label">WARNING — Lock Wait Timeouts: $TIMEOUTS (timeout: ${TIMEOUT_VAL}s)</div>
        <p>Transactions exceeded the lock wait timeout and were rolled back.</p>
        <div class="remediation">
            <strong>Remediation:</strong><br>
            1. Identify blocking transactions from <code>data_lock_waits</code> output<br>
            2. Kill long-blocking transactions if business-acceptable<br>
            3. For parallel batch jobs: lower timeout to 5-10s + implement retry<br>
            4. Fix root cause: missing indexes, wide range locks, or long transactions
        </div>
    </div>
HTML
else
    cat >> "$REPORT_FILE" << HTML
    <div class="severity-ok">
        <div class="severity-label">OK — No Lock Wait Timeouts</div>
        <p>No transactions have timed out waiting for locks.</p>
    </div>
HTML
fi

echo "</div></div>" >> "$REPORT_FILE"

# ============================================================================
# Blocking Pairs (if any)
# ============================================================================
BLOCKING_DATA=$(collect_data "
SELECT
    r.trx_id AS waiting_trx,
    r.trx_mysql_thread_id AS waiting_pid,
    TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_sec,
    LEFT(r.trx_query, 80) AS waiting_query,
    b.trx_id AS blocking_trx,
    b.trx_mysql_thread_id AS blocking_pid,
    b.trx_state AS blocking_state,
    LEFT(b.trx_query, 80) AS blocking_query,
    dl.LOCK_MODE,
    dl.OBJECT_NAME
FROM information_schema.INNODB_TRX r
JOIN performance_schema.data_lock_waits dlw ON r.trx_id = dlw.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX b ON b.trx_id = dlw.BLOCKING_ENGINE_TRANSACTION_ID
JOIN performance_schema.data_locks dl ON dl.ENGINE_LOCK_ID = dlw.BLOCKING_ENGINE_LOCK_ID
LIMIT 20;
")

BLOCKING_COUNT=$(echo "$BLOCKING_DATA" | tail -n +2 | wc -l)
if [ "$BLOCKING_COUNT" -gt 1 ] 2>/dev/null; then
    cat >> "$REPORT_FILE" << HTML
<div class="section">
    <div class="section-header">🔒 Active Lock Blocking (Who blocks whom)</div>
    <div class="section-body">
        <table>
            <tr><th>Waiting PID</th><th>Wait(s)</th><th>Waiting Query</th><th>Blocked By PID</th><th>Blocker State</th><th>Blocker Query</th><th>Lock Mode</th><th>Table</th></tr>
HTML
    echo "$BLOCKING_DATA" | tail -n +2 | while IFS=$'\t' read -r wtrx wpid wsec wquery btrx bpid bstate bquery lmode obj; do
        [ -z "$wpid" ] && continue
        cat >> "$REPORT_FILE" << HTML
            <tr><td>$wpid</td><td style="color:var(--red)">$wsec</td><td><code>$wquery</code></td><td>$bpid</td><td>$bstate</td><td><code>$bquery</code></td><td style="color:var(--yellow)">$lmode</td><td>$obj</td></tr>
HTML
    done
    echo "</table></div></div>" >> "$REPORT_FILE"
fi

# ============================================================================
# Top Wait Events from Performance Schema
# ============================================================================
WAIT_EVENTS=$(collect_data "
SELECT EVENT_NAME, COUNT_STAR, ROUND(SUM_TIMER_WAIT/1000000000, 2) AS total_ms, ROUND(AVG_TIMER_WAIT/1000000000, 2) AS avg_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME != 'idle' AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC LIMIT 15;
")

cat >> "$REPORT_FILE" << 'HTML'
<div class="section">
    <div class="section-header">⏱ Top Wait Events (Performance Schema)</div>
    <div class="section-body">
        <table>
            <tr><th>Wait Event</th><th>Count</th><th>Total (ms)</th><th>Avg (ms)</th></tr>
HTML

echo "$WAIT_EVENTS" | tail -n +2 | while IFS=$'\t' read -r ename cnt total avg; do
    [ -z "$ename" ] && continue
    highlight=""
    echo "$ename" | grep -q "lock\|aurora" && highlight="style=\"color:var(--yellow)\""
    cat >> "$REPORT_FILE" << HTML
            <tr><td $highlight>$ename</td><td>$cnt</td><td>$total</td><td>$avg</td></tr>
HTML
done

echo "</table></div></div>" >> "$REPORT_FILE"

# ============================================================================
# Statements with highest lock time
# ============================================================================
LOCK_STMTS=$(collect_data "
SELECT LEFT(DIGEST_TEXT, 100) AS query, COUNT_STAR AS execs,
       ROUND(SUM_LOCK_TIME/1000000000, 2) AS lock_ms,
       ROUND(AVG_TIMER_WAIT/1000000000, 2) AS avg_ms,
       ROUND(MAX_TIMER_WAIT/1000000000, 2) AS max_ms
FROM performance_schema.events_statements_summary_by_digest
WHERE SUM_LOCK_TIME > 0
ORDER BY SUM_LOCK_TIME DESC LIMIT 10;
")

cat >> "$REPORT_FILE" << 'HTML'
<div class="section">
    <div class="section-header">📝 Statements with Highest Lock Time</div>
    <div class="section-body">
        <table>
            <tr><th>Query (truncated)</th><th>Execs</th><th>Lock Time (ms)</th><th>Avg (ms)</th><th>Max (ms)</th></tr>
HTML

echo "$LOCK_STMTS" | tail -n +2 | while IFS=$'\t' read -r query execs lock_ms avg_ms max_ms; do
    [ -z "$query" ] && continue
    cat >> "$REPORT_FILE" << HTML
            <tr><td><code>$query</code></td><td>$execs</td><td style="color:var(--orange)">$lock_ms</td><td>$avg_ms</td><td>$max_ms</td></tr>
HTML
done

echo "</table></div></div>" >> "$REPORT_FILE"

# ============================================================================
# Aurora-specific metrics
# ============================================================================
AURORA_METRICS=$(collect_data "SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';")

cat >> "$REPORT_FILE" << 'HTML'
<div class="section">
    <div class="section-header">☁️ Aurora-Specific Metrics</div>
    <div class="section-body">
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
HTML

echo "$AURORA_METRICS" | tail -n +2 | while IFS=$'\t' read -r name val; do
    [ -z "$name" ] && continue
    cat >> "$REPORT_FILE" << HTML
            <tr><td>$name</td><td>$val</td></tr>
HTML
done

echo "</table></div></div>" >> "$REPORT_FILE"

# ============================================================================
# Footer
# ============================================================================
cat >> "$REPORT_FILE" << HTML
<footer>
    Generated by Aurora MySQL Diagnostic Toolkit | Instance: $SERVER_ID ($ROLE) |
    Aurora $AURORA_VER | $(date '+%Y-%m-%d %H:%M:%S %Z')
</footer>
</div>
<script>
document.querySelectorAll('.collapsible').forEach(el => {
    el.addEventListener('click', () => {
        el.nextElementSibling.classList.toggle('show');
    });
});
</script>
</body>
</html>
HTML

echo ""
echo "[✓] HTML report generated: $REPORT_FILE"
echo ""
echo "    Open in browser:"
echo "      open $REPORT_FILE        (macOS)"
echo "      xdg-open $REPORT_FILE    (Linux)"
echo "      start $REPORT_FILE       (Windows)"
echo ""
