#!/bin/bash
# ============================================================================
# Aurora MySQL Lock Contention Simulation
# Simulates realistic parallel DML contention:
#   - Concurrent UPDATEs on overlapping rows (row lock contention)
#   - SELECT FOR UPDATE competing with UPDATEs (lock waits)
#   - Long-running transactions holding locks (blocking)
#   - INSERT into same index ranges (gap lock contention)
# ============================================================================

AURORA_HOST="${AURORA_HOST:-your-cluster.cluster-xxxxx.region.rds.amazonaws.com}"
AURORA_USER="${AURORA_USER:-admin}"
DB="${AURORA_DB:-qldwh}"
PARALLEL_COUNT="${PARALLEL_COUNT:-50}"
OUTPUT_DIR="$HOME/aurora_lock_test_$(date +%Y%m%d_%H%M%S)"

if [ -z "$MYSQL_PWD" ]; then
    if [ -f "$HOME/.my.cnf" ]; then
        echo "[Info] Using credentials from ~/.my.cnf"
    else
        echo "[ERROR] No credentials found. Set MYSQL_PWD or create ~/.my.cnf"
        echo ""
        echo "Usage:"
        echo "  export AURORA_HOST='your-cluster-endpoint'"
        echo "  export AURORA_USER='your-user'"
        echo "  export MYSQL_PWD='your-password'"
        echo "  export AURORA_DB='your-database'"
        echo "  bash $0"
        exit 1
    fi
fi

# Safety check: prevent accidental execution on production
if [ "${I_CONFIRM_THIS_IS_NOT_PRODUCTION:-}" != "yes" ]; then
    echo "=============================================="
    echo " WARNING: This script MODIFIES DATA"
    echo "=============================================="
    echo ""
    echo " It will:"
    echo "   - DROP and CREATE tables"
    echo "   - INSERT/UPDATE/DELETE rows"
    echo "   - Generate heavy lock contention and deadlocks"
    echo ""
    echo " DO NOT RUN ON PRODUCTION."
    echo ""
    echo " To confirm this is a test environment, run:"
    echo "   export I_CONFIRM_THIS_IS_NOT_PRODUCTION=yes"
    echo "   bash $0"
    echo ""
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

MYSQL_CMD="mysql -h $AURORA_HOST -u $AURORA_USER $DB"

echo "=============================================="
echo " Aurora MySQL Lock Contention Simulation"
echo " Output: $OUTPUT_DIR"
echo " Started: $(date)"
echo "=============================================="
echo ""

# ============================================================================
# SETUP: Create helper table and reset state
# ============================================================================
echo "[Setup] Preparing contention scenario..."

$MYSQL_CMD --batch <<'SQL'
-- Create a hot table for contention testing
DROP TABLE IF EXISTS qldwh.hot_planning_updates;
CREATE TABLE qldwh.hot_planning_updates (
    id INT NOT NULL AUTO_INCREMENT,
    dim_position_id INT NOT NULL,
    planning_cycle_id INT NOT NULL,
    retailbrand_id INT NOT NULL,
    counter INT DEFAULT 0,
    amount DECIMAL(12,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending',
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_position_cycle (dim_position_id, planning_cycle_id),
    INDEX idx_status (status, dim_position_id),
    INDEX idx_brand_position (retailbrand_id, dim_position_id)
) ENGINE=InnoDB;

-- Insert 10000 rows with limited position IDs (to force overlap)
INSERT INTO qldwh.hot_planning_updates (dim_position_id, planning_cycle_id, retailbrand_id, counter, amount, status)
SELECT
    (seq.n MOD 50) + 1 AS dim_position_id,
    (seq.n MOD 10) + 1 AS planning_cycle_id,
    (seq.n MOD 8) + 1 AS retailbrand_id,
    0,
    ROUND(RAND() * 1000, 2),
    ELT(1 + (seq.n MOD 4), 'pending', 'processing', 'completed', 'failed')
FROM (
    SELECT @rownum := @rownum + 1 AS n
    FROM information_schema.COLUMNS a,
         information_schema.COLUMNS b,
         (SELECT @rownum := 0) r
    LIMIT 10000
) seq;

-- Note: Performance schema counters are cumulative.
-- Compare pre/post snapshots rather than truncating (requires SUPER privilege).
-- Uncomment below ONLY if you have SUPER and want a clean baseline:
-- TRUNCATE performance_schema.events_waits_summary_global_by_event_name;
-- TRUNCATE performance_schema.events_statements_summary_by_digest;

SELECT 'Setup complete' AS status, COUNT(*) AS rows_in_hot_table FROM qldwh.hot_planning_updates;
SQL

echo "[Setup] Done."
echo ""

# ============================================================================
# SCENARIO 1: Concurrent UPDATE on overlapping rows (classic row lock contention)
# ============================================================================
run_scenario1_worker() {
    local worker_id=$1
    local position_id=$(( (RANDOM % 10) + 1 ))  # Only 10 positions = high contention
    local outfile="$OUTPUT_DIR/s1_worker_${worker_id}.txt"

    local start_time=$(date +%s%3N)
    $MYSQL_CMD --batch <<SQL > "$outfile" 2>&1
SET SESSION innodb_lock_wait_timeout = 30;
START TRANSACTION;

-- Update rows for a specific position (many workers will hit same position)
UPDATE qldwh.hot_planning_updates
SET counter = counter + 1,
    amount = amount + ROUND(RAND() * 100, 2),
    last_updated = NOW()
WHERE dim_position_id = $position_id
  AND planning_cycle_id IN (1, 2, 3, 4, 5);

-- Simulate some processing time (holds the lock)
SELECT SLEEP(0.5 + RAND());

-- Update the fact table too (wider lock footprint)
UPDATE qldwh.fact_planningcycle
SET planned_sales_qty_tot = planned_sales_qty_tot + ROUND(RAND() * 10, 2)
WHERE dim_position_id = $position_id
  AND planning_cycle_id <= 3
LIMIT 500;

COMMIT;
SQL
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    echo "${worker_id},${duration},${exit_code},scenario1_update" >> "$OUTPUT_DIR/contention_timings.csv"
}

# ============================================================================
# SCENARIO 2: SELECT FOR UPDATE competing with regular UPDATEs
# ============================================================================
run_scenario2_reader() {
    local worker_id=$1
    local position_id=$(( (RANDOM % 10) + 1 ))
    local outfile="$OUTPUT_DIR/s2_reader_${worker_id}.txt"

    local start_time=$(date +%s%3N)
    $MYSQL_CMD --batch <<SQL > "$outfile" 2>&1
SET SESSION innodb_lock_wait_timeout = 30;
START TRANSACTION;

-- SELECT FOR UPDATE locks rows and waits if someone else has them
SELECT dim_position_id, planning_cycle_id, SUM(amount) AS total
FROM qldwh.hot_planning_updates
WHERE dim_position_id = $position_id
  AND status IN ('pending', 'processing')
GROUP BY dim_position_id, planning_cycle_id
FOR UPDATE;

-- Hold the lock while "processing"
SELECT SLEEP(1 + RAND() * 2);

-- Then update status
UPDATE qldwh.hot_planning_updates
SET status = 'completed'
WHERE dim_position_id = $position_id
  AND status = 'pending'
LIMIT 10;

COMMIT;
SQL
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    echo "${worker_id},${duration},${exit_code},scenario2_select_for_update" >> "$OUTPUT_DIR/contention_timings.csv"
}

# ============================================================================
# SCENARIO 3: Long transaction holding locks (simulates your slow query blocking others)
# ============================================================================
run_scenario3_blocker() {
    local worker_id=$1
    local outfile="$OUTPUT_DIR/s3_blocker_${worker_id}.txt"

    local start_time=$(date +%s%3N)
    $MYSQL_CMD --batch <<SQL > "$outfile" 2>&1
SET SESSION innodb_lock_wait_timeout = 30;
START TRANSACTION;

-- Lock a wide range of rows (simulates a long-running report query with lock)
SELECT *
FROM qldwh.hot_planning_updates
WHERE dim_position_id BETWEEN 1 AND 20
FOR UPDATE;

-- Hold locks for 5-8 seconds (simulates processing)
SELECT SLEEP(5 + RAND() * 3);

-- Do a big update while holding the lock
UPDATE qldwh.hot_planning_updates
SET counter = counter + 10
WHERE dim_position_id BETWEEN 1 AND 20;

COMMIT;
SQL
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    echo "${worker_id},${duration},${exit_code},scenario3_blocker" >> "$OUTPUT_DIR/contention_timings.csv"
}

# ============================================================================
# SCENARIO 4: INSERT with gap lock contention (REPEATABLE-READ)
# ============================================================================
run_scenario4_inserter() {
    local worker_id=$1
    local position_id=$(( (RANDOM % 10) + 1 ))
    local outfile="$OUTPUT_DIR/s4_inserter_${worker_id}.txt"

    local start_time=$(date +%s%3N)
    $MYSQL_CMD --batch <<SQL > "$outfile" 2>&1
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET SESSION innodb_lock_wait_timeout = 30;
START TRANSACTION;

-- Delete + re-insert pattern (common in ETL) causes gap locks
DELETE FROM qldwh.hot_planning_updates
WHERE dim_position_id = $position_id
  AND planning_cycle_id = $(( (RANDOM % 5) + 1 ))
  AND status = 'failed'
LIMIT 5;

-- Insert new rows into same range (gap lock conflict with other sessions)
INSERT INTO qldwh.hot_planning_updates (dim_position_id, planning_cycle_id, retailbrand_id, counter, amount, status)
VALUES
    ($position_id, $(( (RANDOM % 5) + 1 )), $(( (RANDOM % 8) + 1 )), 0, ROUND(RAND()*500, 2), 'pending'),
    ($position_id, $(( (RANDOM % 5) + 1 )), $(( (RANDOM % 8) + 1 )), 0, ROUND(RAND()*500, 2), 'pending'),
    ($position_id, $(( (RANDOM % 5) + 1 )), $(( (RANDOM % 8) + 1 )), 0, ROUND(RAND()*500, 2), 'pending');

SELECT SLEEP(0.2 + RAND() * 0.5);

COMMIT;
SQL
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    echo "${worker_id},${duration},${exit_code},scenario4_insert_gap" >> "$OUTPUT_DIR/contention_timings.csv"
}

# ============================================================================
# SCENARIO 5: Mixed read + write on fact table (your original pattern but with writes)
# ============================================================================
run_scenario5_mixed() {
    local worker_id=$1
    local position_id=$(( (RANDOM % 15) + 1 ))
    local outfile="$OUTPUT_DIR/s5_mixed_${worker_id}.txt"

    local start_time=$(date +%s%3N)
    $MYSQL_CMD --batch <<SQL > "$outfile" 2>&1
SET SESSION innodb_lock_wait_timeout = 30;
START TRANSACTION;

-- Read with shared lock (blocks exclusive locks from other sessions)
SELECT
    dim_position_id,
    planning_cycle_id,
    retailbrand_id,
    SUM(planned_sales_qty_tot) AS planned_total,
    SUM(forecast_sales_qty) AS forecast_total
FROM qldwh.fact_planningcycle
WHERE dim_position_id = $position_id
GROUP BY dim_position_id, planning_cycle_id, retailbrand_id
LOCK IN SHARE MODE;

-- Then try to update (needs exclusive lock - may conflict with other SHARE holders)
UPDATE qldwh.fact_planningcycle
SET forecast_sales_qty = planned_sales_qty_tot * (0.9 + RAND() * 0.2),
    updated_at = NOW()
WHERE dim_position_id = $position_id
  AND planning_cycle_id <= 5
LIMIT 200;

COMMIT;
SQL
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    echo "${worker_id},${duration},${exit_code},scenario5_mixed_rw" >> "$OUTPUT_DIR/contention_timings.csv"
}

# ============================================================================
# DIAGNOSTIC CAPTURE (runs throughout the test)
# ============================================================================
capture_lock_diagnostics() {
    local interval=$1
    local duration=$2
    local outfile="$OUTPUT_DIR/lock_diagnostics_live.txt"
    local elapsed=0

    echo "=== LOCK CONTENTION DIAGNOSTIC CAPTURE ===" > "$outfile"
    echo "=== Started: $(date) ===" >> "$outfile"

    while [ $elapsed -lt $duration ]; do
        echo "" >> "$outfile"
        echo "====== SNAPSHOT $(date) (${elapsed}s) ======" >> "$outfile"

        $MYSQL_CMD --batch -e "
        SELECT '--- PROCESSLIST (non-idle) ---' AS section;
        SELECT id, user, time, state, LEFT(info, 100) AS query
        FROM information_schema.PROCESSLIST
        WHERE command != 'Sleep' AND info IS NOT NULL
        ORDER BY time DESC
        LIMIT 30;

        SELECT '--- DATA LOCK WAITS (BLOCKING PAIRS) ---' AS section;
        SELECT
            r.trx_id AS waiting_trx,
            r.trx_mysql_thread_id AS waiting_pid,
            r.trx_state AS waiting_state,
            TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_sec,
            LEFT(r.trx_query, 100) AS waiting_query,
            b.trx_id AS blocking_trx,
            b.trx_mysql_thread_id AS blocking_pid,
            b.trx_state AS blocking_state,
            LEFT(b.trx_query, 100) AS blocking_query,
            dl.LOCK_MODE,
            dl.LOCK_TYPE,
            dl.OBJECT_NAME,
            dl.INDEX_NAME,
            dl.LOCK_DATA
        FROM information_schema.INNODB_TRX r
        JOIN performance_schema.data_lock_waits dlw
            ON r.trx_id = dlw.REQUESTING_ENGINE_TRANSACTION_ID
        JOIN information_schema.INNODB_TRX b
            ON b.trx_id = dlw.BLOCKING_ENGINE_TRANSACTION_ID
        JOIN performance_schema.data_locks dl
            ON dl.ENGINE_LOCK_ID = dlw.BLOCKING_ENGINE_LOCK_ID
        LIMIT 20;

        SELECT '--- ALL DATA LOCKS (Current) ---' AS section;
        SELECT LOCK_TYPE, LOCK_MODE, LOCK_STATUS, OBJECT_NAME, COUNT(*) AS cnt
        FROM performance_schema.data_locks
        GROUP BY LOCK_TYPE, LOCK_MODE, LOCK_STATUS, OBJECT_NAME
        ORDER BY cnt DESC;

        SELECT '--- GAP LOCKS ---' AS section;
        SELECT ENGINE_TRANSACTION_ID, OBJECT_NAME, INDEX_NAME, LOCK_MODE, LOCK_STATUS, LOCK_DATA
        FROM performance_schema.data_locks
        WHERE LOCK_MODE LIKE '%GAP%' OR LOCK_MODE LIKE '%,GAP'
        LIMIT 20;

        SELECT '--- INNODB TRX DETAIL ---' AS section;
        SELECT
            trx_id,
            trx_state,
            TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_sec,
            trx_rows_locked,
            trx_rows_modified,
            trx_lock_structs,
            trx_lock_memory_bytes,
            trx_tables_locked,
            LEFT(trx_query, 80) AS query,
            trx_operation_state
        FROM information_schema.INNODB_TRX
        WHERE trx_state != 'RUNNING' OR trx_rows_locked > 0
        ORDER BY trx_rows_locked DESC
        LIMIT 20;

        SELECT '--- ROW LOCK STATS ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';

        SELECT '--- AURORA LOCK MANAGER ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';

        SELECT '--- THREADS ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Threads_connected';
        SHOW GLOBAL STATUS LIKE 'Threads_running';

        SELECT '--- DEADLOCK COUNT ---' AS section;
        SELECT NAME, COUNT FROM information_schema.INNODB_METRICS WHERE NAME='lock_deadlocks';

        SELECT '--- LOCK WAIT TIMEOUTS ---' AS section;
        SELECT NAME, COUNT FROM information_schema.INNODB_METRICS WHERE NAME='lock_timeouts';

        SELECT '--- AURORA WAIT EVENTS (lock related) ---' AS section;
        SELECT EVENT_NAME, COUNT_STAR, SUM_TIMER_WAIT/1000000000 AS total_ms
        FROM performance_schema.events_waits_summary_global_by_event_name
        WHERE (EVENT_NAME LIKE '%lock%' OR EVENT_NAME LIKE '%aurora%')
          AND COUNT_STAR > 0
        ORDER BY SUM_TIMER_WAIT DESC
        LIMIT 15;

        SELECT '--- sys.innodb_lock_waits ---' AS section;
        SELECT * FROM sys.innodb_lock_waits;
        " >> "$outfile" 2>&1

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo "" >> "$outfile"
    echo "=== CAPTURE ENDED: $(date) ===" >> "$outfile"
}

# ============================================================================
# PRE-TEST BASELINE
# ============================================================================
echo "[Baseline] Capturing pre-test state..."
$MYSQL_CMD --batch -e "
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS WHERE NAME IN ('lock_deadlocks','lock_timeouts','lock_row_lock_waits');
" > "$OUTPUT_DIR/pre_test_baseline.txt" 2>&1

# ============================================================================
# RUN ALL SCENARIOS IN PARALLEL
# ============================================================================
echo ""
echo "[Test] Launching lock contention scenarios..."
echo "  - Scenario 1: $PARALLEL_COUNT concurrent UPDATEs on overlapping rows"
echo "  - Scenario 2: $((PARALLEL_COUNT/2)) SELECT FOR UPDATE competing"
echo "  - Scenario 3: 5 long-running blockers"
echo "  - Scenario 4: $((PARALLEL_COUNT/2)) INSERT/DELETE gap lock conflicts"
echo "  - Scenario 5: $((PARALLEL_COUNT/2)) mixed read+write on fact table"
echo ""

echo "worker_id,duration_ms,exit_code,scenario" > "$OUTPUT_DIR/contention_timings.csv"

# Start diagnostic capture (every 3 seconds, for 180 seconds)
capture_lock_diagnostics 3 180 &
DIAG_PID=$!

test_start=$(date +%s%3N)

# Launch Scenario 3 first (blockers that hold locks)
for ((i=1; i<=5; i++)); do
    run_scenario3_blocker "s3_$i" &
done

sleep 1

# Launch Scenario 1: Concurrent UPDATEs
for ((i=1; i<=PARALLEL_COUNT; i++)); do
    run_scenario1_worker "s1_$i" &
    if [ $((i % 10)) -eq 0 ]; then sleep 0.2; fi
done

# Launch Scenario 2: SELECT FOR UPDATE
for ((i=1; i<=$((PARALLEL_COUNT/2)); i++)); do
    run_scenario2_reader "s2_$i" &
    if [ $((i % 10)) -eq 0 ]; then sleep 0.2; fi
done

# Launch Scenario 4: Gap lock contention
for ((i=1; i<=$((PARALLEL_COUNT/2)); i++)); do
    run_scenario4_inserter "s4_$i" &
    if [ $((i % 10)) -eq 0 ]; then sleep 0.2; fi
done

# Launch Scenario 5: Mixed read/write
for ((i=1; i<=$((PARALLEL_COUNT/2)); i++)); do
    run_scenario5_mixed "s5_$i" &
    if [ $((i % 10)) -eq 0 ]; then sleep 0.2; fi
done

# Wait for all workers
echo "[Test] Waiting for all workers to complete..."
wait $(jobs -rp | grep -v $DIAG_PID)

test_end=$(date +%s%3N)
test_total=$((test_end - test_start))

# Stop diagnostics
kill $DIAG_PID 2>/dev/null
wait $DIAG_PID 2>/dev/null

echo ""
echo "[Test] All workers complete. Total time: ${test_total}ms"

# ============================================================================
# POST-TEST SNAPSHOT
# ============================================================================
echo ""
echo "[Post-Test] Capturing final state..."
$MYSQL_CMD --batch -e "
SELECT '=== POST-TEST LOCK METRICS ===' AS section;
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';
SHOW GLOBAL STATUS LIKE 'Innodb_deadlocks';
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS WHERE NAME IN ('lock_deadlocks','lock_timeouts','lock_row_lock_waits','lock_row_lock_time');

SELECT '=== STATEMENTS WITH LOCK TIME ===' AS section;
SELECT LEFT(DIGEST_TEXT, 100) AS query, COUNT_STAR AS execs,
       SUM_LOCK_TIME/1000000000 AS lock_ms,
       AVG_TIMER_WAIT/1000000000 AS avg_ms,
       MAX_TIMER_WAIT/1000000000 AS max_ms
FROM performance_schema.events_statements_summary_by_digest
WHERE SUM_LOCK_TIME > 0
ORDER BY SUM_LOCK_TIME DESC
LIMIT 15;

SELECT '=== ERROR SUMMARY ===' AS section;
SELECT ERROR_NAME, SUM_ERROR_RAISED, FIRST_SEEN, LAST_SEEN
FROM performance_schema.events_errors_summary_global_by_error
WHERE ERROR_NAME IN ('ER_LOCK_WAIT_TIMEOUT','ER_LOCK_DEADLOCK')
  AND SUM_ERROR_RAISED > 0;
" > "$OUTPUT_DIR/post_test_snapshot.txt" 2>&1

# ============================================================================
# GENERATE SUMMARY
# ============================================================================
echo "[Summary] Generating report..."

# Stats per scenario
cat > "$OUTPUT_DIR/CONTENTION_REPORT.txt" <<REPORT
==============================================================================
AURORA MYSQL LOCK CONTENTION TEST REPORT
Generated: $(date)
==============================================================================

Instance: $AURORA_HOST
Total Test Duration: ${test_total}ms

==============================================================================
PER-SCENARIO RESULTS:
==============================================================================

REPORT

for scenario in scenario1_update scenario2_select_for_update scenario3_blocker scenario4_insert_gap scenario5_mixed_rw; do
    total=$(grep "$scenario" "$OUTPUT_DIR/contention_timings.csv" | wc -l)
    failed=$(grep "$scenario" "$OUTPUT_DIR/contention_timings.csv" | awk -F',' '$3!=0' | wc -l)
    succeeded=$((total - failed))

    if [ $succeeded -gt 0 ]; then
        min=$(grep "$scenario" "$OUTPUT_DIR/contention_timings.csv" | awk -F',' '$3==0{print $2}' | sort -n | head -1)
        max=$(grep "$scenario" "$OUTPUT_DIR/contention_timings.csv" | awk -F',' '$3==0{print $2}' | sort -n | tail -1)
        avg=$(grep "$scenario" "$OUTPUT_DIR/contention_timings.csv" | awk -F',' '$3==0{sum+=$2;c++} END{if(c>0) printf "%.0f",sum/c}')
    else
        min="N/A"; max="N/A"; avg="N/A"
    fi

    cat >> "$OUTPUT_DIR/CONTENTION_REPORT.txt" <<STATS
--- $scenario ---
  Workers: $total | Success: $succeeded | Failed: $failed
  Min: ${min}ms | Avg: ${avg}ms | Max: ${max}ms

STATS
done

cat >> "$OUTPUT_DIR/CONTENTION_REPORT.txt" <<REPORT

==============================================================================
KEY METRICS (Pre vs Post):
==============================================================================

--- PRE-TEST ---
$(cat "$OUTPUT_DIR/pre_test_baseline.txt")

--- POST-TEST ---
$(cat "$OUTPUT_DIR/post_test_snapshot.txt")

==============================================================================
FILES:
==============================================================================
- contention_timings.csv      : All worker timings with scenario labels
- lock_diagnostics_live.txt   : Live lock snapshots every 3s during test
- pre_test_baseline.txt       : Metrics before test
- post_test_snapshot.txt      : Metrics after test
- s1_worker_*.txt             : Scenario 1 outputs
- s2_reader_*.txt             : Scenario 2 outputs
- s3_blocker_*.txt            : Scenario 3 outputs
- s4_inserter_*.txt           : Scenario 4 outputs
- s5_mixed_*.txt              : Scenario 5 outputs
- CONTENTION_REPORT.txt       : This summary

==============================================================================
WHAT TO LOOK FOR:
==============================================================================
1. lock_diagnostics_live.txt: Look for DATA LOCK WAITS section showing
   which transactions are blocking which, and what LOCK_MODE/LOCK_DATA
2. Innodb_row_lock_waits increase = row lock contention occurred
3. Innodb_row_lock_time increase = how long total spent waiting for locks
4. lock_deadlocks count > 0 = deadlocks detected
5. lock_timeouts count > 0 = lock wait timeouts occurred
6. GAP locks in diagnostics = isolation level causing phantom protection
7. scenario timing: if avg >> min, contention was the bottleneck
==============================================================================
REPORT

echo ""
echo "=============================================="
echo " LOCK CONTENTION TEST COMPLETE"
echo "=============================================="
echo ""
cat "$OUTPUT_DIR/CONTENTION_REPORT.txt"
