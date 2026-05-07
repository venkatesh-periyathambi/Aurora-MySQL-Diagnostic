-- ============================================================================
-- Aurora MySQL 3.x (MySQL 8.0 Compatible) Diagnostic Script
-- Locks, Latches & Performance Schema
-- Use Case: Query works individually but fails/blocks when run in parallel
-- ============================================================================
-- PREREQUISITES:
--   1. performance_schema must be enabled (parameter group: performance_schema=1)
--   2. User needs: SELECT on performance_schema, PROCESS privilege
--   3. Run this WHILE the parallel workload is active to capture live state
-- ============================================================================
-- AURORA-SPECIFIC NOTES:
--   - Storage I/O is handled by Aurora storage layer (no local page flushing)
--   - Redo logs are offloaded to Aurora storage (no local log files)
--   - Some InnoDB variables (io_capacity, log_buffer_size, etc.) don't exist
--   - @@tx_isolation is removed; use @@transaction_isolation
--   - Buffer pool dirty pages will show 0 (Aurora doesn't flush from DB tier)
--   - Aurora has its own lock manager with dedicated memory tracking
-- ============================================================================

-- ============================================================================
-- SECTION 1: AURORA INSTANCE IDENTITY & SERVER STATE
-- ============================================================================

SELECT '=== AURORA INSTANCE INFO ===' AS section;
SELECT
    VERSION() AS mysql_version,
    @@aurora_version AS aurora_engine_version,
    @@aurora_server_id AS aurora_server_id,
    @@hostname AS hostname,
    @@innodb_read_only AS is_reader_instance,
    NOW() AS run_timestamp;

SHOW GLOBAL STATUS LIKE 'Uptime';

SELECT '=== ACTIVE THREADS ===' AS section;
SELECT
    id,
    user,
    host,
    db,
    command,
    time AS seconds_running,
    state,
    LEFT(info, 200) AS query_preview
FROM information_schema.PROCESSLIST
WHERE command != 'Sleep'
ORDER BY time DESC;

-- ============================================================================
-- SECTION 2: InnoDB LOCK DIAGNOSTICS
-- ============================================================================

SELECT '=== INNODB ENGINE STATUS ===' AS section;
SHOW ENGINE INNODB STATUS;

SELECT '=== CURRENT DATA LOCKS (performance_schema.data_locks) ===' AS section;
SELECT
    ENGINE,
    ENGINE_LOCK_ID,
    ENGINE_TRANSACTION_ID,
    THREAD_ID,
    EVENT_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    PARTITION_NAME,
    SUBPARTITION_NAME,
    INDEX_NAME,
    OBJECT_INSTANCE_BEGIN,
    LOCK_TYPE,
    LOCK_MODE,
    LOCK_STATUS,
    LOCK_DATA
FROM performance_schema.data_locks
ORDER BY ENGINE_TRANSACTION_ID, LOCK_TYPE;

SELECT '=== DATA LOCK WAITS (Who is blocking whom) ===' AS section;
SELECT
    dlw.REQUESTING_ENGINE_LOCK_ID,
    dlw.REQUESTING_ENGINE_TRANSACTION_ID AS waiting_trx_id,
    dlw.REQUESTING_THREAD_ID AS waiting_thread,
    dlw.BLOCKING_ENGINE_LOCK_ID,
    dlw.BLOCKING_ENGINE_TRANSACTION_ID AS blocking_trx_id,
    dlw.BLOCKING_THREAD_ID AS blocking_thread
FROM performance_schema.data_lock_waits dlw;

SELECT '=== DETAILED LOCK WAIT ANALYSIS ===' AS section;
SELECT
    r.trx_id AS waiting_trx_id,
    r.trx_mysql_thread_id AS waiting_thread,
    r.trx_state AS waiting_state,
    LEFT(r.trx_query, 200) AS waiting_query,
    r.trx_wait_started,
    TIMESTAMPDIFF(SECOND, r.trx_wait_started, NOW()) AS wait_seconds,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_state AS blocking_state,
    LEFT(b.trx_query, 200) AS blocking_query,
    b.trx_started AS blocking_trx_started,
    dl.OBJECT_SCHEMA AS locked_schema,
    dl.OBJECT_NAME AS locked_table,
    dl.INDEX_NAME AS locked_index,
    dl.LOCK_TYPE,
    dl.LOCK_MODE,
    dl.LOCK_DATA
FROM information_schema.INNODB_TRX r
JOIN performance_schema.data_lock_waits dlw
    ON r.trx_id = dlw.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX b
    ON b.trx_id = dlw.BLOCKING_ENGINE_TRANSACTION_ID
JOIN performance_schema.data_locks dl
    ON dl.ENGINE_LOCK_ID = dlw.BLOCKING_ENGINE_LOCK_ID;

SELECT '=== ALL ACTIVE INNODB TRANSACTIONS ===' AS section;
SELECT
    trx_id,
    trx_state,
    trx_started,
    TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS trx_age_seconds,
    trx_mysql_thread_id,
    trx_tables_in_use,
    trx_tables_locked,
    trx_lock_structs,
    trx_rows_locked,
    trx_rows_modified,
    trx_isolation_level,
    trx_unique_checks,
    trx_foreign_key_checks,
    LEFT(trx_query, 200) AS current_query,
    trx_operation_state,
    trx_weight,
    trx_lock_memory_bytes,
    trx_autocommit_non_locking
FROM information_schema.INNODB_TRX
ORDER BY trx_started;

SELECT '=== TRANSACTION ISOLATION LEVEL ===' AS section;
SELECT @@transaction_isolation AS transaction_isolation_level;

-- ============================================================================
-- SECTION 3: METADATA LOCKS (MDL)
-- ============================================================================

SELECT '=== METADATA LOCKS ===' AS section;
SELECT
    OBJECT_TYPE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COLUMN_NAME,
    LOCK_TYPE,
    LOCK_DURATION,
    LOCK_STATUS,
    SOURCE,
    OWNER_THREAD_ID,
    OWNER_EVENT_ID
FROM performance_schema.metadata_locks
WHERE OBJECT_SCHEMA NOT IN ('performance_schema', 'information_schema', 'mysql')
ORDER BY OBJECT_SCHEMA, OBJECT_NAME, LOCK_STATUS;

SELECT '=== MDL LOCK WAITERS (Blocked DDL/DML) ===' AS section;
SELECT
    ml_waiting.OBJECT_SCHEMA,
    ml_waiting.OBJECT_NAME,
    ml_waiting.LOCK_TYPE AS waiting_lock_type,
    ml_waiting.LOCK_STATUS AS waiting_status,
    ml_waiting.OWNER_THREAD_ID AS waiting_thread,
    t_waiting.PROCESSLIST_ID AS waiting_pid,
    LEFT(t_waiting.PROCESSLIST_INFO, 200) AS waiting_query,
    ml_blocking.LOCK_TYPE AS blocking_lock_type,
    ml_blocking.LOCK_STATUS AS blocking_status,
    ml_blocking.OWNER_THREAD_ID AS blocking_thread,
    t_blocking.PROCESSLIST_ID AS blocking_pid,
    LEFT(t_blocking.PROCESSLIST_INFO, 200) AS blocking_query
FROM performance_schema.metadata_locks ml_waiting
JOIN performance_schema.metadata_locks ml_blocking
    ON ml_waiting.OBJECT_SCHEMA = ml_blocking.OBJECT_SCHEMA
    AND ml_waiting.OBJECT_NAME = ml_blocking.OBJECT_NAME
    AND ml_waiting.LOCK_STATUS = 'PENDING'
    AND ml_blocking.LOCK_STATUS = 'GRANTED'
JOIN performance_schema.threads t_waiting
    ON ml_waiting.OWNER_THREAD_ID = t_waiting.THREAD_ID
JOIN performance_schema.threads t_blocking
    ON ml_blocking.OWNER_THREAD_ID = t_blocking.THREAD_ID;

-- ============================================================================
-- SECTION 4: TABLE LOCKS
-- ============================================================================

SELECT '=== TABLE LOCK WAITS SUMMARY ===' AS section;
SELECT
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.table_lock_waits_summary_by_table
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

SELECT '=== TABLE IO WAITS SUMMARY ===' AS section;
SELECT
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COUNT_STAR AS total_io_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_io_wait_ms,
    COUNT_READ,
    SUM_TIMER_READ / 1000000000 AS total_read_wait_ms,
    COUNT_WRITE,
    SUM_TIMER_WRITE / 1000000000 AS total_write_wait_ms,
    COUNT_FETCH,
    COUNT_INSERT,
    COUNT_UPDATE,
    COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA NOT IN ('performance_schema', 'mysql', 'information_schema', 'sys')
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

SELECT '=== TABLE IO WAITS BY INDEX ===' AS section;
SELECT
    OBJECT_SCHEMA,
    OBJECT_NAME,
    INDEX_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    COUNT_READ,
    COUNT_WRITE,
    COUNT_FETCH,
    COUNT_INSERT,
    COUNT_UPDATE,
    COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA NOT IN ('performance_schema', 'mysql', 'information_schema', 'sys')
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

-- ============================================================================
-- SECTION 5: MUTEX & LATCH DIAGNOSTICS
-- ============================================================================

SELECT '=== INNODB MUTEXES (Latches) ===' AS section;
SHOW ENGINE INNODB MUTEX;

SELECT '=== PERFORMANCE SCHEMA MUTEX INSTANCES (Currently Locked) ===' AS section;
SELECT
    NAME AS mutex_name,
    OBJECT_INSTANCE_BEGIN,
    LOCKED_BY_THREAD_ID
FROM performance_schema.mutex_instances
WHERE LOCKED_BY_THREAD_ID IS NOT NULL
ORDER BY NAME;

SELECT '=== MUTEX WAIT SUMMARY (Top by total wait time) ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE 'wait/synch/mutex%'
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

SELECT '=== AURORA LOCK THREAD SLOT FUTEX (Row lock contention indicator) ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE '%aurora_lock_thread_slot_futex%'
    OR EVENT_NAME LIKE '%aurora%lock%'
    AND COUNT_STAR > 0;

SELECT '=== RWLOCK WAIT SUMMARY (Top by total wait time) ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE 'wait/synch/rwlock%'
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

SELECT '=== RWLOCK INSTANCES (Currently Locked) ===' AS section;
SELECT
    NAME,
    OBJECT_INSTANCE_BEGIN,
    WRITE_LOCKED_BY_THREAD_ID,
    READ_LOCKED_BY_COUNT
FROM performance_schema.rwlock_instances
WHERE WRITE_LOCKED_BY_THREAD_ID IS NOT NULL
    OR READ_LOCKED_BY_COUNT > 0
ORDER BY NAME;

SELECT '=== CONDITION VARIABLE WAITS ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE 'wait/synch/cond%'
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

-- ============================================================================
-- SECTION 6: DEADLOCK DIAGNOSTICS
-- ============================================================================

SELECT '=== DEADLOCK COUNT (from InnoDB metrics) ===' AS section;
SELECT
    NAME,
    COUNT,
    MAX_COUNT,
    AVG_COUNT,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE NAME = 'lock_deadlocks';

SELECT '=== ROW LOCK STATISTICS ===' AS section;
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_time%';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_waits';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_current_waits';

SELECT '=== INNODB LOCK METRICS (Detailed) ===' AS section;
SELECT
    NAME,
    COUNT,
    MAX_COUNT,
    AVG_COUNT,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE NAME LIKE 'lock_%'
ORDER BY COUNT DESC;

-- ============================================================================
-- SECTION 7: WAIT EVENT ANALYSIS (What threads are waiting on)
-- ============================================================================

SELECT '=== CURRENT WAIT EVENTS (Active Threads) ===' AS section;
SELECT
    t.THREAD_ID,
    t.PROCESSLIST_ID,
    t.PROCESSLIST_USER,
    t.PROCESSLIST_DB,
    t.PROCESSLIST_COMMAND,
    t.PROCESSLIST_STATE,
    ew.EVENT_NAME AS wait_event,
    ew.TIMER_WAIT / 1000000000 AS wait_ms,
    ew.OBJECT_SCHEMA,
    ew.OBJECT_NAME,
    ew.INDEX_NAME,
    ew.OPERATION
FROM performance_schema.threads t
JOIN performance_schema.events_waits_current ew
    ON t.THREAD_ID = ew.THREAD_ID
WHERE t.PROCESSLIST_COMMAND != 'Sleep'
    AND ew.EVENT_NAME != 'idle'
ORDER BY ew.TIMER_WAIT DESC;

SELECT '=== TOP WAIT EVENTS GLOBALLY ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME != 'idle'
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

SELECT '=== AURORA-SPECIFIC WAIT EVENTS ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_waits,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE (EVENT_NAME LIKE '%aurora%'
    OR EVENT_NAME LIKE '%redo_log_flush%')
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC;

SELECT '=== WAIT EVENTS BY THREAD (Top waiters) ===' AS section;
SELECT
    ews.THREAD_ID,
    t.PROCESSLIST_ID,
    t.PROCESSLIST_USER,
    t.PROCESSLIST_DB,
    ews.EVENT_NAME,
    ews.COUNT_STAR AS wait_count,
    ews.SUM_TIMER_WAIT / 1000000000 AS total_wait_ms
FROM performance_schema.events_waits_summary_by_thread_by_event_name ews
JOIN performance_schema.threads t ON ews.THREAD_ID = t.THREAD_ID
WHERE ews.COUNT_STAR > 0
    AND ews.EVENT_NAME NOT LIKE 'idle'
    AND t.PROCESSLIST_USER IS NOT NULL
ORDER BY ews.SUM_TIMER_WAIT DESC
LIMIT 50;

-- ============================================================================
-- SECTION 8: STATEMENT & STAGE ANALYSIS
-- ============================================================================

SELECT '=== CURRENT STAGE EVENTS (What each thread is doing) ===' AS section;
SELECT
    t.THREAD_ID,
    t.PROCESSLIST_ID,
    t.PROCESSLIST_USER,
    t.PROCESSLIST_DB,
    es.EVENT_NAME AS stage,
    es.TIMER_WAIT / 1000000000 AS stage_wait_ms,
    es.WORK_COMPLETED,
    es.WORK_ESTIMATED
FROM performance_schema.threads t
JOIN performance_schema.events_stages_current es
    ON t.THREAD_ID = es.THREAD_ID
WHERE t.PROCESSLIST_COMMAND != 'Sleep'
ORDER BY es.TIMER_WAIT DESC;

SELECT '=== TOP STAGES BY WAIT TIME ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_stages_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

SELECT '=== STATEMENTS CURRENTLY RUNNING ===' AS section;
SELECT
    t.THREAD_ID,
    t.PROCESSLIST_ID,
    t.PROCESSLIST_USER,
    t.PROCESSLIST_DB,
    esc.DIGEST_TEXT,
    esc.TIMER_WAIT / 1000000000 AS elapsed_ms,
    esc.LOCK_TIME / 1000000000 AS lock_time_ms,
    esc.ROWS_EXAMINED,
    esc.ROWS_SENT,
    esc.ROWS_AFFECTED,
    esc.CREATED_TMP_TABLES,
    esc.CREATED_TMP_DISK_TABLES,
    esc.NO_INDEX_USED,
    esc.NO_GOOD_INDEX_USED
FROM performance_schema.threads t
JOIN performance_schema.events_statements_current esc
    ON t.THREAD_ID = esc.THREAD_ID
WHERE t.PROCESSLIST_COMMAND != 'Sleep'
    AND esc.DIGEST_TEXT IS NOT NULL
ORDER BY esc.TIMER_WAIT DESC;

SELECT '=== STATEMENTS WITH HIGHEST LOCK TIME (Historical) ===' AS section;
SELECT
    DIGEST_TEXT,
    COUNT_STAR AS exec_count,
    SUM_LOCK_TIME / 1000000000 AS total_lock_time_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_latency_ms,
    SUM_ROWS_EXAMINED,
    SUM_ROWS_SENT,
    FIRST_SEEN,
    LAST_SEEN
FROM performance_schema.events_statements_summary_by_digest
WHERE SUM_LOCK_TIME > 0
ORDER BY SUM_LOCK_TIME DESC
LIMIT 20;

SELECT '=== STATEMENTS WITH HIGHEST LATENCY VARIANCE (Contention signal) ===' AS section;
SELECT
    DIGEST_TEXT,
    COUNT_STAR AS exec_count,
    MIN_TIMER_WAIT / 1000000000 AS min_latency_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_latency_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_latency_ms,
    (MAX_TIMER_WAIT - MIN_TIMER_WAIT) / 1000000000 AS latency_range_ms,
    SUM_LOCK_TIME / 1000000000 AS total_lock_time_ms
FROM performance_schema.events_statements_summary_by_digest
WHERE COUNT_STAR > 1
ORDER BY (MAX_TIMER_WAIT - MIN_TIMER_WAIT) DESC
LIMIT 20;

-- ============================================================================
-- SECTION 9: GAP LOCKS & NEXT-KEY LOCKS (Critical for parallel issues)
-- ============================================================================

SELECT '=== GAP LOCKS AND NEXT-KEY LOCKS ===' AS section;
SELECT
    ENGINE_TRANSACTION_ID,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    INDEX_NAME,
    LOCK_TYPE,
    LOCK_MODE,
    LOCK_STATUS,
    LOCK_DATA
FROM performance_schema.data_locks
WHERE LOCK_MODE LIKE '%GAP%'
    OR LOCK_MODE LIKE '%,GAP'
    OR LOCK_MODE = 'X'
    OR LOCK_MODE = 'S'
ORDER BY OBJECT_SCHEMA, OBJECT_NAME, LOCK_DATA;

SELECT '=== LOCK MODE DISTRIBUTION ===' AS section;
SELECT
    LOCK_TYPE,
    LOCK_MODE,
    LOCK_STATUS,
    COUNT(*) AS lock_count
FROM performance_schema.data_locks
GROUP BY LOCK_TYPE, LOCK_MODE, LOCK_STATUS
ORDER BY lock_count DESC;

-- ============================================================================
-- SECTION 10: AUTO-INCREMENT LOCKS (Common parallel insert issue)
-- ============================================================================

SELECT '=== AUTO-INCREMENT LOCK MODE ===' AS section;
SELECT @@innodb_autoinc_lock_mode AS autoinc_lock_mode;
-- 0 = traditional (table-level), 1 = consecutive, 2 = interleaved (best for parallel)

SELECT '=== AUTO-INCREMENT RELATED WAITS ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE '%autoinc%'
    AND COUNT_STAR > 0;

-- ============================================================================
-- SECTION 11: AURORA-COMPATIBLE INNODB CONFIGURATION
-- ============================================================================

SELECT '=== INNODB LOCK/CONCURRENCY CONFIGURATION (Aurora-compatible) ===' AS section;
SELECT
    @@innodb_lock_wait_timeout AS lock_wait_timeout_sec,
    @@innodb_deadlock_detect AS deadlock_detect,
    @@innodb_thread_concurrency AS thread_concurrency,
    @@innodb_thread_sleep_delay AS thread_sleep_delay_us,
    @@innodb_spin_wait_delay AS spin_wait_delay,
    @@innodb_sync_spin_loops AS sync_spin_loops,
    @@innodb_adaptive_hash_index AS adaptive_hash_index,
    @@innodb_purge_threads AS purge_threads,
    @@innodb_flush_log_at_trx_commit AS flush_log_at_trx_commit;

SELECT '=== CONNECTION & THREAD SETTINGS ===' AS section;
SELECT
    @@max_connections AS max_connections,
    @@thread_cache_size AS thread_cache_size,
    @@table_open_cache AS table_open_cache,
    @@table_open_cache_instances AS table_open_cache_instances;

SHOW GLOBAL STATUS LIKE 'Threads_%';
SHOW GLOBAL STATUS LIKE 'Connections';
SHOW GLOBAL STATUS LIKE 'Max_used_connections';

-- ============================================================================
-- SECTION 12: AURORA-SPECIFIC STORAGE & LOCK MANAGER METRICS
-- ============================================================================

SELECT '=== AURORA LOCK MANAGER MEMORY ===' AS section;
SHOW GLOBAL STATUS LIKE 'Aurora_lockmgr%';

SELECT '=== AURORA COMMIT & STATEMENT LATENCY ===' AS section;
SHOW GLOBAL STATUS LIKE 'AuroraDb_commit%';
SHOW GLOBAL STATUS LIKE 'AuroraDb_select_stmt_duration';
SHOW GLOBAL STATUS LIKE 'AuroraDb_insert_stmt_duration';
SHOW GLOBAL STATUS LIKE 'AuroraDb_update_stmt_duration';
SHOW GLOBAL STATUS LIKE 'AuroraDb_delete_stmt_duration';
SHOW GLOBAL STATUS LIKE 'AuroraDb_ddl_stmt_duration';

SELECT '=== AURORA PARALLEL QUERY METRICS ===' AS section;
SHOW GLOBAL STATUS LIKE 'Aurora_pq%';

SELECT '=== AURORA WRITE FORWARDING (if using reader for writes) ===' AS section;
SHOW GLOBAL STATUS LIKE 'Aurora_fwd%';

SELECT '=== AURORA THREAD POOL ===' AS section;
SHOW GLOBAL STATUS LIKE 'Aurora_thread_pool%';

SELECT '=== AURORA EXTERNAL CONNECTIONS ===' AS section;
SHOW GLOBAL STATUS LIKE 'Aurora_external%';

-- ============================================================================
-- SECTION 13: AURORA REDO LOG & STORAGE LAYER WAITS
-- ============================================================================

SELECT '=== AURORA REDO LOG FLUSH WAITS (Storage layer latency) ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE EVENT_NAME LIKE '%redo_log_flush%'
    OR EVENT_NAME LIKE '%aurora_redo%'
    OR EVENT_NAME LIKE '%log%'
    AND COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 15;

SELECT '=== UNDO LOG / HISTORY LIST LENGTH ===' AS section;
SELECT
    NAME,
    COUNT AS value,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE NAME = 'trx_rseg_history_len';

SHOW GLOBAL STATUS LIKE 'Innodb_history_list_length';

-- ============================================================================
-- SECTION 14: INNODB METRICS (Lock, Latch, Transaction subsystems)
-- ============================================================================

SELECT '=== INNODB METRICS - LOCK SUBSYSTEM ===' AS section;
SELECT
    NAME,
    SUBSYSTEM,
    COUNT,
    MAX_COUNT,
    AVG_COUNT,
    STATUS,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE SUBSYSTEM = 'lock'
    AND COUNT > 0
ORDER BY COUNT DESC;

SELECT '=== INNODB METRICS - TRANSACTION SUBSYSTEM ===' AS section;
SELECT
    NAME,
    SUBSYSTEM,
    COUNT,
    MAX_COUNT,
    AVG_COUNT,
    STATUS,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE SUBSYSTEM = 'transaction'
    AND COUNT > 0
ORDER BY COUNT DESC;

SELECT '=== INNODB METRICS - ADAPTIVE HASH INDEX ===' AS section;
SELECT
    NAME,
    SUBSYSTEM,
    COUNT,
    MAX_COUNT,
    AVG_COUNT,
    STATUS,
    COMMENT
FROM information_schema.INNODB_METRICS
WHERE SUBSYSTEM = 'adaptive_hash_index'
    AND COUNT > 0
ORDER BY COUNT DESC;

-- ============================================================================
-- SECTION 15: BUFFER POOL (Aurora-relevant fields only)
-- ============================================================================

SELECT '=== INNODB BUFFER POOL STATUS ===' AS section;
SELECT * FROM information_schema.INNODB_BUFFER_POOL_STATS;

-- ============================================================================
-- SECTION 16: MEMORY & TEMP TABLE CONTENTION
-- ============================================================================

SELECT '=== MEMORY ALLOCATION EVENTS (Top consumers) ===' AS section;
SELECT
    EVENT_NAME,
    CURRENT_COUNT_USED,
    CURRENT_NUMBER_OF_BYTES_USED,
    HIGH_COUNT_USED,
    HIGH_NUMBER_OF_BYTES_USED
FROM performance_schema.memory_summary_global_by_event_name
WHERE CURRENT_NUMBER_OF_BYTES_USED > 1048576
ORDER BY CURRENT_NUMBER_OF_BYTES_USED DESC
LIMIT 20;

SELECT '=== TEMP TABLE USAGE ===' AS section;
SHOW GLOBAL STATUS LIKE 'Created_tmp%';

-- ============================================================================
-- SECTION 17: FILE I/O (Aurora storage layer perspective)
-- ============================================================================

SELECT '=== FILE I/O BY EVENT ===' AS section;
SELECT
    EVENT_NAME,
    COUNT_STAR AS total_ops,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    AVG_TIMER_WAIT / 1000000000 AS avg_wait_ms,
    MAX_TIMER_WAIT / 1000000000 AS max_wait_ms,
    SUM_NUMBER_OF_BYTES_READ AS bytes_read,
    SUM_NUMBER_OF_BYTES_WRITE AS bytes_written
FROM performance_schema.file_summary_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

SELECT '=== FILE I/O BY INSTANCE (Hot Files) ===' AS section;
SELECT
    FILE_NAME,
    EVENT_NAME,
    COUNT_STAR AS total_ops,
    SUM_TIMER_WAIT / 1000000000 AS total_wait_ms,
    COUNT_READ,
    SUM_TIMER_READ / 1000000000 AS read_wait_ms,
    COUNT_WRITE,
    SUM_TIMER_WRITE / 1000000000 AS write_wait_ms
FROM performance_schema.file_summary_by_instance
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;

-- ============================================================================
-- SECTION 18: PREPARED STATEMENTS
-- ============================================================================

SELECT '=== PREPARED STATEMENT INSTANCES ===' AS section;
SELECT
    OBJECT_INSTANCE_BEGIN,
    STATEMENT_ID,
    STATEMENT_NAME,
    LEFT(SQL_TEXT, 200) AS sql_text,
    OWNER_THREAD_ID,
    OWNER_EVENT_ID,
    TIMER_PREPARE / 1000000000 AS prepare_time_ms,
    COUNT_REPREPARE,
    COUNT_EXECUTE,
    SUM_TIMER_EXECUTE / 1000000000 AS total_exec_ms,
    SUM_LOCK_TIME / 1000000000 AS total_lock_ms,
    SUM_ROWS_EXAMINED,
    SUM_ROWS_SENT
FROM performance_schema.prepared_statements_instances
ORDER BY SUM_LOCK_TIME DESC
LIMIT 20;

-- ============================================================================
-- SECTION 19: TRANSACTION HISTORY
-- ============================================================================

SELECT '=== ACTIVE TRANSACTION EVENTS ===' AS section;
SELECT
    THREAD_ID,
    EVENT_NAME,
    STATE,
    TRX_ID,
    TIMER_WAIT / 1000000000 AS duration_ms,
    ACCESS_MODE,
    ISOLATION_LEVEL,
    AUTOCOMMIT,
    NESTING_EVENT_TYPE,
    NUMBER_OF_SAVEPOINTS,
    NUMBER_OF_ROLLBACK_TO_SAVEPOINT,
    NUMBER_OF_RELEASE_SAVEPOINT
FROM performance_schema.events_transactions_current
WHERE STATE = 'ACTIVE'
ORDER BY TIMER_WAIT DESC;

SELECT '=== TRANSACTION SUMMARY BY THREAD ===' AS section;
SELECT
    ets.THREAD_ID,
    t.PROCESSLIST_USER,
    t.PROCESSLIST_DB,
    ets.COUNT_STAR AS trx_count,
    ets.SUM_TIMER_WAIT / 1000000000 AS total_trx_time_ms,
    ets.AVG_TIMER_WAIT / 1000000000 AS avg_trx_time_ms,
    ets.MAX_TIMER_WAIT / 1000000000 AS max_trx_time_ms
FROM performance_schema.events_transactions_summary_by_thread_by_event_name ets
JOIN performance_schema.threads t ON ets.THREAD_ID = t.THREAD_ID
WHERE ets.COUNT_STAR > 0
    AND t.PROCESSLIST_USER IS NOT NULL
ORDER BY ets.SUM_TIMER_WAIT DESC
LIMIT 20;

-- ============================================================================
-- SECTION 20: ERROR & WARNING SUMMARY
-- ============================================================================

SELECT '=== ERRORS BY THREAD (Lock related) ===' AS section;
SELECT
    THREAD_ID,
    ERROR_NUMBER,
    ERROR_NAME,
    SQL_STATE,
    SUM_ERROR_RAISED,
    SUM_ERROR_HANDLED,
    FIRST_SEEN,
    LAST_SEEN
FROM performance_schema.events_errors_summary_by_thread_by_error
WHERE ERROR_NAME IN (
    'ER_LOCK_WAIT_TIMEOUT',
    'ER_LOCK_DEADLOCK',
    'ER_LOCK_TABLE_FULL',
    'ER_LOCK_ABORTED',
    'ER_CANT_LOCK',
    'ER_TABLE_DEF_CHANGED'
)
AND SUM_ERROR_RAISED > 0
ORDER BY LAST_SEEN DESC;

SELECT '=== GLOBAL ERROR SUMMARY (Lock related) ===' AS section;
SELECT
    ERROR_NUMBER,
    ERROR_NAME,
    SQL_STATE,
    SUM_ERROR_RAISED,
    SUM_ERROR_HANDLED,
    FIRST_SEEN,
    LAST_SEEN
FROM performance_schema.events_errors_summary_global_by_error
WHERE ERROR_NAME IN (
    'ER_LOCK_WAIT_TIMEOUT',
    'ER_LOCK_DEADLOCK',
    'ER_LOCK_TABLE_FULL',
    'ER_LOCK_ABORTED',
    'ER_CANT_LOCK',
    'ER_TABLE_DEF_CHANGED',
    'ER_QUERY_TIMEOUT'
)
AND SUM_ERROR_RAISED > 0;

-- ============================================================================
-- SECTION 21: SYS SCHEMA VIEWS
-- ============================================================================

SELECT '=== sys.innodb_lock_waits ===' AS section;
SELECT * FROM sys.innodb_lock_waits;

SELECT '=== sys.schema_table_lock_waits ===' AS section;
SELECT * FROM sys.schema_table_lock_waits;

SELECT '=== sys.session (Active sessions with waits) ===' AS section;
SELECT
    thd_id,
    conn_id,
    user,
    db,
    command,
    state,
    time,
    current_statement,
    rows_examined,
    rows_sent,
    tmp_tables,
    tmp_disk_tables,
    current_memory
FROM sys.session
WHERE command != 'Sleep'
ORDER BY time DESC;

SELECT '=== sys.statements_with_runtimes_in_95th_percentile ===' AS section;
SELECT *
FROM sys.statements_with_runtimes_in_95th_percentile
ORDER BY avg_latency DESC
LIMIT 20;

SELECT '=== sys.statements_with_full_table_scans ===' AS section;
SELECT *
FROM sys.statements_with_full_table_scans
ORDER BY total_latency DESC
LIMIT 20;

-- ============================================================================
-- SECTION 22: AURORA REPLICA LAG & GLOBAL DB STATUS (if applicable)
-- ============================================================================

SELECT '=== AURORA REPLICA STATUS ===' AS section;
SELECT
    SERVER_ID,
    SESSION_ID,
    LAST_UPDATE_TIMESTAMP,
    REPLICA_LAG_IN_MILLISECONDS,
    CPU
FROM information_schema.replica_host_status;

-- ============================================================================
-- SECTION 23: PERFORMANCE SCHEMA INSTRUMENTATION CHECK
-- ============================================================================

SELECT '=== ENABLED INSTRUMENTS (Lock/Wait related) ===' AS section;
SELECT
    NAME,
    ENABLED,
    TIMED
FROM performance_schema.setup_instruments
WHERE NAME LIKE '%lock%'
    OR NAME LIKE '%mutex%'
    OR NAME LIKE '%rwlock%'
    OR NAME LIKE '%wait/synch%'
    OR NAME LIKE '%aurora%'
ORDER BY ENABLED DESC, NAME
LIMIT 60;

SELECT '=== ENABLED CONSUMERS ===' AS section;
SELECT * FROM performance_schema.setup_consumers;

-- ============================================================================
-- SECTION 24: ENABLE INSTRUMENTS (Run separately if needed)
-- ============================================================================

-- Uncomment and run these if instruments are disabled:
-- UPDATE performance_schema.setup_instruments SET ENABLED='YES', TIMED='YES'
--   WHERE NAME LIKE 'wait/synch/%';
-- UPDATE performance_schema.setup_instruments SET ENABLED='YES', TIMED='YES'
--   WHERE NAME LIKE 'wait/lock/%';
-- UPDATE performance_schema.setup_consumers SET ENABLED='YES'
--   WHERE NAME LIKE 'events_waits%';
-- UPDATE performance_schema.setup_consumers SET ENABLED='YES'
--   WHERE NAME LIKE 'events_stages%';
-- UPDATE performance_schema.setup_consumers SET ENABLED='YES'
--   WHERE NAME LIKE 'events_statements%';
-- UPDATE performance_schema.setup_consumers SET ENABLED='YES'
--   WHERE NAME LIKE 'events_transactions%';

-- ============================================================================
-- SECTION 25: DYNAMIC RECOMMENDATIONS (based on current instance state)
-- ============================================================================

SELECT '=== DYNAMIC RECOMMENDATIONS (based on detected conditions) ===' AS section;

-- Deadlock analysis
SELECT '--- DEADLOCK ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN cnt.deadlocks > 50 THEN CONCAT('[CRITICAL] ', cnt.deadlocks, ' deadlocks detected. Immediate action required.')
        WHEN cnt.deadlocks > 10 THEN CONCAT('[WARNING] ', cnt.deadlocks, ' deadlocks detected. Investigate blocking patterns.')
        WHEN cnt.deadlocks > 0 THEN CONCAT('[INFO] ', cnt.deadlocks, ' deadlocks detected. Monitor for increase.')
        ELSE '[OK] No deadlocks detected.'
    END AS deadlock_status,
    CASE
        WHEN cnt.deadlocks > 0 THEN 'REMEDIATION: (1) Run SHOW ENGINE INNODB STATUS and check LATEST DETECTED DEADLOCK section for the exact cycle. (2) Ensure all transactions access tables/rows in the SAME ORDER. (3) Keep transactions short - commit frequently. (4) Add indexes to reduce lock footprint. (5) Consider READ-COMMITTED isolation to eliminate gap locks.'
        ELSE 'No action needed.'
    END AS deadlock_remediation
FROM (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_deadlocks') cnt(deadlocks);

-- Row lock contention analysis
SELECT '--- ROW LOCK CONTENTION ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN rlw.VARIABLE_VALUE > 100 THEN CONCAT('[CRITICAL] ', rlw.VARIABLE_VALUE, ' row lock waits. Heavy contention.')
        WHEN rlw.VARIABLE_VALUE > 20 THEN CONCAT('[WARNING] ', rlw.VARIABLE_VALUE, ' row lock waits. Moderate contention.')
        WHEN rlw.VARIABLE_VALUE > 0 THEN CONCAT('[INFO] ', rlw.VARIABLE_VALUE, ' row lock waits. Low contention.')
        ELSE '[OK] No row lock waits.'
    END AS lock_wait_status,
    CASE
        WHEN rlt.VARIABLE_VALUE > 0 THEN CONCAT('Average wait: ', rlt_avg.VARIABLE_VALUE, 'ms | Max wait: ', rlt_max.VARIABLE_VALUE, 'ms')
        ELSE 'N/A'
    END AS wait_times,
    CASE
        WHEN rlw.VARIABLE_VALUE > 20 THEN 'REMEDIATION: (1) Check data_lock_waits output above for blocking transaction pairs. (2) Identify hot rows/indexes being contended. (3) Reduce transaction duration. (4) Add covering indexes. (5) Consider optimistic locking (retry on deadlock).'
        ELSE 'No action needed.'
    END AS lock_remediation
FROM
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_waits') rlw,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time') rlt,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time_avg') rlt_avg,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time_max') rlt_max;

-- Gap lock analysis
SELECT '--- GAP LOCK ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN gap_count > 10 THEN CONCAT('[CRITICAL] ', gap_count, ' gap locks detected. These block INSERT_INTENTION locks and cause deadlocks in parallel workloads.')
        WHEN gap_count > 0 THEN CONCAT('[WARNING] ', gap_count, ' gap locks detected. May cause parallel INSERT/DELETE contention.')
        ELSE '[OK] No gap locks detected at this moment.'
    END AS gap_lock_status,
    CASE
        WHEN gap_count > 0 AND iso.VARIABLE_VALUE = 'REPEATABLE-READ' THEN 'REMEDIATION: (1) Switch to READ-COMMITTED isolation via DB parameter group (CAUTION: affects all new sessions cluster-wide; test thoroughly first). (2) Use unique/exact-match WHERE clauses instead of ranges. (3) For INSERT-heavy workloads, ensure innodb_autoinc_lock_mode=2.'
        WHEN gap_count > 0 THEN 'REMEDIATION: (1) Use narrower WHERE clauses. (2) Add indexes covering the search predicates. (3) Avoid DELETE + INSERT patterns (use REPLACE or INSERT ON DUPLICATE KEY UPDATE).'
        ELSE 'No action needed.'
    END AS gap_lock_remediation,
    iso.VARIABLE_VALUE AS current_isolation_level
FROM
    (SELECT COUNT(*) AS gap_count FROM performance_schema.data_locks WHERE LOCK_MODE LIKE '%GAP%') gaps,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'transaction_isolation') iso;

-- Long transaction analysis
SELECT '--- LONG TRANSACTION ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN max_age > 60 THEN CONCAT('[CRITICAL] Longest active transaction: ', max_age, 's. Long transactions hold locks and block others.')
        WHEN max_age > 30 THEN CONCAT('[WARNING] Longest active transaction: ', max_age, 's. May cause lock accumulation.')
        WHEN max_age > 0 THEN CONCAT('[INFO] Longest active transaction: ', max_age, 's.')
        ELSE '[OK] No long-running transactions.'
    END AS long_trx_status,
    CASE
        WHEN max_age > 30 THEN 'REMEDIATION: (1) Identify the long transaction from INNODB_TRX output above. (2) Break large transactions into smaller batches. (3) Avoid SELECT ... FOR UPDATE on large result sets. (4) Set innodb_lock_wait_timeout lower (e.g., 10s) to fail fast. (5) Implement application-level retry on ER_LOCK_WAIT_TIMEOUT.'
        ELSE 'No action needed.'
    END AS long_trx_remediation,
    active_count AS active_transactions,
    total_locked AS total_rows_locked_across_all_trx
FROM (
    SELECT
        COALESCE(MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())), 0) AS max_age,
        COUNT(*) AS active_count,
        COALESCE(SUM(trx_rows_locked), 0) AS total_locked
    FROM information_schema.INNODB_TRX
) trx_summary;

-- Lock wait timeout analysis
SELECT '--- LOCK WAIT TIMEOUT ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN cnt.timeouts > 10 THEN CONCAT('[CRITICAL] ', cnt.timeouts, ' lock wait timeouts. Transactions are failing due to contention.')
        WHEN cnt.timeouts > 0 THEN CONCAT('[WARNING] ', cnt.timeouts, ' lock wait timeouts detected.')
        ELSE '[OK] No lock wait timeouts.'
    END AS timeout_status,
    CONCAT('Current innodb_lock_wait_timeout = ', @@innodb_lock_wait_timeout, 's') AS current_setting,
    CASE
        WHEN cnt.timeouts > 0 THEN 'REMEDIATION: (1) Identify blocking transactions (see data_lock_waits above). (2) Kill long-blocking transactions if acceptable. (3) For parallel batch jobs, lower timeout to 5-10s and implement retry logic. (4) Fix root cause: missing indexes, wide range locks, or long transactions.'
        ELSE 'No action needed.'
    END AS timeout_remediation
FROM (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_timeouts') cnt(timeouts);

-- Metadata lock analysis
SELECT '--- METADATA LOCK ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN pending_count > 0 THEN CONCAT('[WARNING] ', pending_count, ' pending metadata locks. DDL is blocked by active transactions.')
        ELSE '[OK] No pending metadata locks.'
    END AS mdl_status,
    CASE
        WHEN pending_count > 0 THEN 'REMEDIATION: (1) Identify the blocking session holding the MDL (see metadata_locks output above). (2) Wait for the blocking transaction to complete or kill it. (3) Schedule DDL during low-traffic periods. (4) Use pt-online-schema-change or gh-ost for non-blocking DDL.'
        ELSE 'No action needed.'
    END AS mdl_remediation
FROM (
    SELECT COUNT(*) AS pending_count
    FROM performance_schema.metadata_locks
    WHERE LOCK_STATUS = 'PENDING'
) mdl;

-- Connection/thread saturation
SELECT '--- CONNECTION SATURATION ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN (tc.VARIABLE_VALUE / @@max_connections * 100) > 90 THEN CONCAT('[CRITICAL] ', tc.VARIABLE_VALUE, '/', @@max_connections, ' connections used (', ROUND(tc.VARIABLE_VALUE / @@max_connections * 100), '%). Near max_connections limit.')
        WHEN (tc.VARIABLE_VALUE / @@max_connections * 100) > 70 THEN CONCAT('[WARNING] ', tc.VARIABLE_VALUE, '/', @@max_connections, ' connections used (', ROUND(tc.VARIABLE_VALUE / @@max_connections * 100), '%).')
        ELSE CONCAT('[OK] ', tc.VARIABLE_VALUE, '/', @@max_connections, ' connections used (', ROUND(tc.VARIABLE_VALUE / @@max_connections * 100), '%).')
    END AS connection_status,
    CASE
        WHEN (tc.VARIABLE_VALUE / @@max_connections * 100) > 70 THEN 'REMEDIATION: (1) Increase max_connections in parameter group. (2) Use connection pooling (RDS Proxy, ProxySQL, application-side pool). (3) Close idle connections. (4) Check for connection leaks in application code.'
        ELSE 'No action needed.'
    END AS connection_remediation
FROM (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') tc;

-- History list / purge lag
SELECT '--- PURGE LAG ANALYSIS ---' AS section;
SELECT
    CASE
        WHEN hll.COUNT > 100000 THEN CONCAT('[CRITICAL] History list length: ', hll.COUNT, '. Purge is severely lagged. Long-running transactions preventing cleanup.')
        WHEN hll.COUNT > 10000 THEN CONCAT('[WARNING] History list length: ', hll.COUNT, '. Purge lag building up.')
        ELSE CONCAT('[OK] History list length: ', hll.COUNT, '.')
    END AS purge_status,
    CASE
        WHEN hll.COUNT > 10000 THEN 'REMEDIATION: (1) Identify and terminate long-running read transactions. (2) Avoid long-running mysqldump or reporting queries on the writer. (3) Use a reader instance for long analytical queries. (4) Check innodb_purge_threads (increase if CPU allows).'
        ELSE 'No action needed.'
    END AS purge_remediation
FROM (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len') hll;

-- Auto-increment lock mode check
SELECT '--- AUTO-INCREMENT LOCK MODE ---' AS section;
SELECT
    CASE
        WHEN @@innodb_autoinc_lock_mode = 0 THEN '[CRITICAL] innodb_autoinc_lock_mode=0 (traditional). Table-level lock for every INSERT. Severe bottleneck for parallel inserts.'
        WHEN @@innodb_autoinc_lock_mode = 1 THEN '[INFO] innodb_autoinc_lock_mode=1 (consecutive). Good for most workloads but holds lock for bulk INSERTs.'
        ELSE '[OK] innodb_autoinc_lock_mode=2 (interleaved). Best for parallel insert performance.'
    END AS autoinc_status,
    CASE
        WHEN @@innodb_autoinc_lock_mode < 2 THEN 'REMEDIATION: Set innodb_autoinc_lock_mode=2 in parameter group. Safe when using ROW-based replication (Aurora default). Allows concurrent inserts without table-level auto-inc lock.'
        ELSE 'No action needed.'
    END AS autoinc_remediation,
    @@innodb_autoinc_lock_mode AS current_value;

-- Overall summary
SELECT '--- OVERALL ASSESSMENT ---' AS section;
SELECT
    CONCAT(
        'Deadlocks: ', dl.COUNT,
        ' | Row lock waits: ', rlw.VARIABLE_VALUE,
        ' | Lock timeouts: ', lt.COUNT,
        ' | Active trx: ', trx.cnt,
        ' | Max trx age: ', trx.max_age, 's',
        ' | History list: ', hll.COUNT,
        ' | Threads connected: ', tc.VARIABLE_VALUE, '/', @@max_connections
    ) AS instance_health_summary
FROM
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_deadlocks') dl,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_waits') rlw,
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'lock_timeouts') lt,
    (SELECT COUNT(*) AS cnt, COALESCE(MAX(TIMESTAMPDIFF(SECOND, trx_started, NOW())), 0) AS max_age FROM information_schema.INNODB_TRX) trx,
    (SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len') hll,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') tc;

-- ============================================================================
-- END OF AURORA MYSQL DIAGNOSTIC SCRIPT
-- ============================================================================
SELECT '=== DIAGNOSTIC COMPLETE ===' AS section, NOW() AS completed_at_time;
