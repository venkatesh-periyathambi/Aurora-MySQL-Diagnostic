#!/bin/bash
# ============================================================================
# Aurora MySQL Parallel Query Test & Diagnostic Capture
# Tests a planning cycle query individually and then in parallel (100 sessions)
# while capturing performance metrics at the instance level
# ============================================================================

AURORA_HOST="${AURORA_HOST:-your-cluster.cluster-xxxxx.region.rds.amazonaws.com}"
AURORA_USER="${AURORA_USER:-admin}"
DB="${AURORA_DB:-qldwh}"
PARALLEL_COUNT="${PARALLEL_COUNT:-100}"
OUTPUT_DIR="$HOME/aurora_parallel_test_$(date +%Y%m%d_%H%M%S)"

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

mkdir -p "$OUTPUT_DIR"

MYSQL_CMD="mysql -h $AURORA_HOST -u $AURORA_USER $DB"

# ============================================================================
# Generate random position IDs for each query execution (simulates real usage)
# ============================================================================
generate_position_ids() {
    local count=$((20 + RANDOM % 30))
    local ids=""
    for ((i=1; i<=count; i++)); do
        local id=$((1 + RANDOM % 1000))
        if [ -z "$ids" ]; then
            ids="$id"
        else
            ids="$ids, $id"
        fi
    done
    echo "$ids"
}

# ============================================================================
# The test query (matches your real-world pattern)
# ============================================================================
build_query() {
    local position_ids="$1"
    cat <<EOF
SELECT
    dim_position_id,
    planning_cycle_id,
    retailbrand_id,
    planning_cycle_year,
    assortment_season_id,
    assortment_season,
    assortment_season_lifecycle,
    week_in_season,
    start_date,
    end_date,
    SUM(planned_sales_qty_tot) AS planned_sales_qty_tot,
    SUM(forecast_sales_qty) AS forecast_sales_qty
FROM qldwh.fact_planningcycle
    USE INDEX (fk_fact_planningcycle_dim_positions1_idx)
LEFT OUTER JOIN qldwh.dim_items
    ON fact_planningcycle.dim_item_id = dim_items.dim_item_id
INNER JOIN qldwh.dim_stores
    ON fact_planningcycle.dim_store_id = dim_stores.dim_store_id
WHERE dim_position_id IN ($position_ids)
GROUP BY
    dim_position_id,
    planning_cycle_id,
    retailbrand_id,
    planning_cycle_year,
    assortment_season_id,
    assortment_season,
    assortment_season_lifecycle,
    week_in_season,
    start_date,
    end_date;
EOF
}

# ============================================================================
# Diagnostic capture (runs in background during parallel test)
# ============================================================================
capture_diagnostics() {
    local interval=$1
    local duration=$2
    local outfile="$OUTPUT_DIR/diagnostics_live.txt"
    local elapsed=0

    echo "=== DIAGNOSTIC CAPTURE STARTED AT $(date) ===" > "$outfile"

    while [ $elapsed -lt $duration ]; do
        echo "" >> "$outfile"
        echo "========== SNAPSHOT AT $(date) (elapsed: ${elapsed}s) ==========" >> "$outfile"

        $MYSQL_CMD --batch -e "
        SELECT '--- ACTIVE PROCESSLIST ---' AS section;
        SELECT id, user, db, command, time, state, LEFT(info, 150) AS query
        FROM information_schema.PROCESSLIST
        WHERE command != 'Sleep' AND info IS NOT NULL
        ORDER BY time DESC;

        SELECT '--- DATA LOCK WAITS (Blocking) ---' AS section;
        SELECT
            r.trx_id AS waiting_trx,
            r.trx_mysql_thread_id AS waiting_pid,
            TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_sec,
            LEFT(r.trx_query, 120) AS waiting_query,
            b.trx_id AS blocking_trx,
            b.trx_mysql_thread_id AS blocking_pid,
            b.trx_state AS blocking_state
        FROM information_schema.INNODB_TRX r
        JOIN performance_schema.data_lock_waits dlw
            ON r.trx_id = dlw.REQUESTING_ENGINE_TRANSACTION_ID
        JOIN information_schema.INNODB_TRX b
            ON b.trx_id = dlw.BLOCKING_ENGINE_TRANSACTION_ID;

        SELECT '--- LOCK COUNT & MODE ---' AS section;
        SELECT LOCK_TYPE, LOCK_MODE, LOCK_STATUS, COUNT(*) AS cnt
        FROM performance_schema.data_locks
        GROUP BY LOCK_TYPE, LOCK_MODE, LOCK_STATUS
        ORDER BY cnt DESC;

        SELECT '--- GAP LOCKS ---' AS section;
        SELECT ENGINE_TRANSACTION_ID, OBJECT_NAME, INDEX_NAME, LOCK_MODE, LOCK_STATUS, LOCK_DATA
        FROM performance_schema.data_locks
        WHERE LOCK_MODE LIKE '%GAP%'
        LIMIT 20;

        SELECT '--- METADATA LOCK WAITS ---' AS section;
        SELECT
            ml_w.OBJECT_NAME,
            ml_w.LOCK_TYPE AS waiting_type,
            ml_w.OWNER_THREAD_ID AS waiting_thd,
            ml_b.LOCK_TYPE AS blocking_type,
            ml_b.OWNER_THREAD_ID AS blocking_thd
        FROM performance_schema.metadata_locks ml_w
        JOIN performance_schema.metadata_locks ml_b
            ON ml_w.OBJECT_SCHEMA = ml_b.OBJECT_SCHEMA
            AND ml_w.OBJECT_NAME = ml_b.OBJECT_NAME
            AND ml_w.LOCK_STATUS = 'PENDING'
            AND ml_b.LOCK_STATUS = 'GRANTED'
        LIMIT 20;

        SELECT '--- TOP WAIT EVENTS (Current) ---' AS section;
        SELECT EVENT_NAME, COUNT_STAR, SUM_TIMER_WAIT/1000000000 AS total_ms
        FROM performance_schema.events_waits_summary_global_by_event_name
        WHERE EVENT_NAME != 'idle' AND COUNT_STAR > 0
        ORDER BY SUM_TIMER_WAIT DESC
        LIMIT 10;

        SELECT '--- AURORA LOCK MANAGER ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';

        SELECT '--- INNODB ROW LOCK STATUS ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';

        SELECT '--- THREAD/CONNECTION COUNT ---' AS section;
        SHOW GLOBAL STATUS LIKE 'Threads_connected';
        SHOW GLOBAL STATUS LIKE 'Threads_running';

        SELECT '--- INNODB TRX SUMMARY ---' AS section;
        SELECT COUNT(*) AS active_trx,
               MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())) AS longest_trx_sec,
               SUM(trx_rows_locked) AS total_rows_locked,
               SUM(trx_lock_memory_bytes) AS total_lock_memory
        FROM information_schema.INNODB_TRX;
        " >> "$outfile" 2>&1

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo "" >> "$outfile"
    echo "=== DIAGNOSTIC CAPTURE ENDED AT $(date) ===" >> "$outfile"
}

# ============================================================================
# Run a single query and capture timing
# ============================================================================
run_single_query() {
    local query_id=$1
    local position_ids=$(generate_position_ids)
    local query=$(build_query "$position_ids")
    local outfile="$OUTPUT_DIR/query_${query_id}.txt"

    local start_time=$(date +%s%3N)
    echo "$query" | $MYSQL_CMD --batch > "$outfile" 2>&1
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    echo "${query_id},${duration},${exit_code}" >> "$OUTPUT_DIR/parallel_timings.csv"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

echo "=============================================="
echo " Aurora MySQL Parallel Query Test"
echo " Output directory: $OUTPUT_DIR"
echo "=============================================="
echo ""

# --- Phase 1: Individual Query Test ---
echo "[Phase 1] Running query INDIVIDUALLY (single session)..."
echo "query_id,duration_ms,exit_code" > "$OUTPUT_DIR/individual_timings.csv"

for run in 1 2 3 4 5; do
    position_ids=$(generate_position_ids)
    query=$(build_query "$position_ids")

    start_time=$(date +%s%3N)
    echo "$query" | $MYSQL_CMD --batch > "$OUTPUT_DIR/individual_run_${run}.txt" 2>&1
    exit_code=$?
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))

    echo "${run},${duration},${exit_code}" >> "$OUTPUT_DIR/individual_timings.csv"
    echo "  Run $run: ${duration}ms (exit: $exit_code)"
done

echo ""
echo "[Phase 1 Complete] Individual query timings saved."
echo ""

# --- Pre-parallel diagnostic snapshot ---
echo "[Phase 2] Capturing PRE-parallel baseline diagnostics..."
$MYSQL_CMD --batch -e "
SELECT '=== PRE-PARALLEL SNAPSHOT ===' AS section;
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
SHOW GLOBAL STATUS LIKE 'Threads_%';
SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';
SELECT COUNT(*) AS active_transactions FROM information_schema.INNODB_TRX;
" > "$OUTPUT_DIR/pre_parallel_snapshot.txt" 2>&1

# --- Phase 3: Parallel Query Test ---
echo "[Phase 3] Running $PARALLEL_COUNT queries IN PARALLEL..."
echo "query_id,duration_ms,exit_code" > "$OUTPUT_DIR/parallel_timings.csv"

# Start diagnostic capture in background (every 2 seconds for 300 seconds max)
capture_diagnostics 2 300 &
DIAG_PID=$!

# Record parallel test start time
parallel_start=$(date +%s%3N)

# Launch all parallel queries
for ((i=1; i<=PARALLEL_COUNT; i++)); do
    run_single_query $i &

    # Small stagger to avoid thundering herd on connection setup
    if [ $((i % 20)) -eq 0 ]; then
        sleep 0.5
    fi
done

# Wait for all parallel queries to finish
wait $(jobs -rp | grep -v $DIAG_PID)

parallel_end=$(date +%s%3N)
parallel_total=$((parallel_end - parallel_start))

# Stop diagnostic capture
kill $DIAG_PID 2>/dev/null
wait $DIAG_PID 2>/dev/null

echo ""
echo "[Phase 3 Complete] Parallel test finished in ${parallel_total}ms"
echo ""

# --- Post-parallel diagnostic snapshot ---
echo "[Phase 4] Capturing POST-parallel diagnostics..."
$MYSQL_CMD --batch -e "
SELECT '=== POST-PARALLEL SNAPSHOT ===' AS section;
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
SHOW GLOBAL STATUS LIKE 'Threads_%';
SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';
SHOW GLOBAL STATUS LIKE 'Innodb_deadlocks';
SELECT COUNT(*) AS active_transactions FROM information_schema.INNODB_TRX;

SELECT '=== STATEMENTS WITH HIGHEST LOCK TIME (during test) ===' AS section;
SELECT DIGEST_TEXT, COUNT_STAR, SUM_LOCK_TIME/1000000000 AS lock_time_ms,
       AVG_TIMER_WAIT/1000000000 AS avg_ms, MAX_TIMER_WAIT/1000000000 AS max_ms
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT LIKE '%fact_planningcycle%'
ORDER BY SUM_LOCK_TIME DESC
LIMIT 10;
" > "$OUTPUT_DIR/post_parallel_snapshot.txt" 2>&1

# --- Phase 5: Generate Summary Report ---
echo "[Phase 5] Generating summary report..."

cat > "$OUTPUT_DIR/SUMMARY_REPORT.txt" <<REPORT
==============================================================================
AURORA MYSQL PARALLEL QUERY TEST - SUMMARY REPORT
Generated: $(date)
==============================================================================

AURORA INSTANCE: $AURORA_HOST
PARALLEL SESSIONS: $PARALLEL_COUNT
TOTAL PARALLEL DURATION: ${parallel_total}ms

------------------------------------------------------------------------------
INDIVIDUAL QUERY TIMINGS (5 runs, sequential):
------------------------------------------------------------------------------
$(cat "$OUTPUT_DIR/individual_timings.csv")

------------------------------------------------------------------------------
PARALLEL QUERY STATISTICS:
------------------------------------------------------------------------------
REPORT

# Calculate parallel stats
if [ -f "$OUTPUT_DIR/parallel_timings.csv" ]; then
    total_queries=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | wc -l)
    failed_queries=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | awk -F',' '$3!=0' | wc -l)
    successful_queries=$((total_queries - failed_queries))

    if [ $successful_queries -gt 0 ]; then
        min_time=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | awk -F',' '$3==0{print $2}' | sort -n | head -1)
        max_time=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | awk -F',' '$3==0{print $2}' | sort -n | tail -1)
        avg_time=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | awk -F',' '$3==0{sum+=$2; cnt++} END{if(cnt>0) printf "%.0f", sum/cnt; else print "N/A"}')
        p95_time=$(tail -n +2 "$OUTPUT_DIR/parallel_timings.csv" | awk -F',' '$3==0{print $2}' | sort -n | awk -v p=0.95 'BEGIN{c=0} {v[c++]=$1} END{idx=int(c*p); print v[idx]}')
    fi

    cat >> "$OUTPUT_DIR/SUMMARY_REPORT.txt" <<STATS
Total Queries Launched:  $total_queries
Successful:              $successful_queries
Failed:                  $failed_queries
Min Latency:             ${min_time:-N/A}ms
Max Latency:             ${max_time:-N/A}ms
Avg Latency:             ${avg_time:-N/A}ms
P95 Latency:             ${p95_time:-N/A}ms
Total Wall Clock Time:   ${parallel_total}ms

STATS
fi

cat >> "$OUTPUT_DIR/SUMMARY_REPORT.txt" <<REPORT
------------------------------------------------------------------------------
FILES IN THIS REPORT:
------------------------------------------------------------------------------
- individual_timings.csv    : Individual run latencies
- parallel_timings.csv      : All parallel query latencies
- diagnostics_live.txt      : Live diagnostic snapshots during parallel test
- pre_parallel_snapshot.txt : Instance state before parallel test
- post_parallel_snapshot.txt: Instance state after parallel test
- query_*.txt               : Individual query outputs
- SUMMARY_REPORT.txt        : This file

------------------------------------------------------------------------------
INTERPRETATION GUIDE:
------------------------------------------------------------------------------
If individual queries are fast but parallel queries are slow, check:
1. diagnostics_live.txt for lock waits and gap locks
2. Compare pre/post snapshots for Innodb_row_lock_waits increase
3. Look for aurora_lock_thread_slot_futex in wait events
4. Check if LOCK_MODE shows GAP locks (isolation level issue)
5. Check Aurora_lockmgr_memory_used growth (many locks held)
==============================================================================
REPORT

echo ""
echo "=============================================="
echo " TEST COMPLETE"
echo "=============================================="
echo ""
echo " Results directory: $OUTPUT_DIR"
echo ""
echo " Key files to review:"
echo "   cat $OUTPUT_DIR/SUMMARY_REPORT.txt"
echo "   cat $OUTPUT_DIR/diagnostics_live.txt"
echo ""
cat "$OUTPUT_DIR/SUMMARY_REPORT.txt"
