-- ============================================================================
-- Aurora MySQL Performance Schema Instrumentation Setup
-- ============================================================================
-- PURPOSE: Enable full wait/lock instrumentation for diagnostic visibility.
--
-- IMPACT ASSESSMENT:
--   - This script MODIFIES performance_schema runtime configuration.
--   - It does NOT modify user data, schemas, or application tables.
--   - It does NOT require a reboot (changes are immediate).
--   - It does NOT persist across reboots (revert = reboot instance).
--   - It adds ~5-10% CPU overhead and additional memory usage.
--   - It is SAFE to run on production R-class instances during investigation.
--
-- IMPORTANT NOTES:
--   1. performance_schema MUST be enabled (parameter group: performance_schema=1)
--      This requires a DB instance REBOOT if not already enabled.
--   2. DO NOT enable on T-class instances (db.t2/t3/t4g) - risk of OOM.
--      Only use on R-class (db.r5/r6g/r7g) or larger.
--   3. Overhead: ~5-10% CPU + additional memory for instance arrays.
--   4. If Performance Insights is enabled in "automatic" mode, it already
--      enables wait/% instruments and events_waits_current consumer.
--   5. Runtime changes (UPDATE setup_*) are lost on reboot.
--      For persistence, configure in the DB parameter group.
--   6. To REVERT: Simply reboot the instance (runtime changes are not persisted).
-- ============================================================================
-- DEFAULT STATE ON AURORA MySQL 3.x (MySQL 8.0):
--   ENABLED by default:  wait/io/*, wait/lock/*, statement/*, transaction/*
--   DISABLED by default: wait/synch/mutex/*, wait/synch/rwlock/*,
--                         wait/synch/cond/*, stage/*
--   Consumers DISABLED:  events_waits_*, events_stages_*
--   Consumers ENABLED:   events_statements_*, events_transactions_* (current+history)
-- ============================================================================

-- Step 1: Verify performance_schema is ON
SELECT
    CASE WHEN @@performance_schema = 1
        THEN '[OK] performance_schema is ENABLED'
        ELSE '[ERROR] performance_schema is DISABLED. Enable it in DB parameter group and reboot.'
    END AS pfs_status;

-- Step 2: Show current instrumentation state before changes
SELECT '=== BEFORE: Instrumentation Summary ===' AS section;
SELECT
    CASE
        WHEN NAME LIKE 'wait/synch/mutex%' THEN 'wait/synch/mutex'
        WHEN NAME LIKE 'wait/synch/rwlock%' THEN 'wait/synch/rwlock'
        WHEN NAME LIKE 'wait/synch/cond%' THEN 'wait/synch/cond'
        WHEN NAME LIKE 'wait/lock%' THEN 'wait/lock'
        WHEN NAME LIKE 'wait/io%' THEN 'wait/io'
        WHEN NAME LIKE 'stage%' THEN 'stage'
        WHEN NAME LIKE 'statement%' THEN 'statement'
        WHEN NAME LIKE 'transaction%' THEN 'transaction'
        ELSE 'other'
    END AS instrument_family,
    SUM(ENABLED = 'YES') AS enabled_count,
    SUM(ENABLED = 'NO') AS disabled_count,
    COUNT(*) AS total
FROM performance_schema.setup_instruments
GROUP BY instrument_family
ORDER BY disabled_count DESC;

SELECT '=== BEFORE: Consumer Status ===' AS section;
SELECT NAME, ENABLED FROM performance_schema.setup_consumers ORDER BY NAME;

-- ============================================================================
-- Step 3: ENABLE CONSUMERS (needed to collect wait/stage data)
-- ============================================================================
SELECT '=== Enabling consumers ===' AS section;

UPDATE performance_schema.setup_consumers SET ENABLED = 'YES'
WHERE NAME IN (
    'events_waits_current',
    'events_waits_history',
    'events_waits_history_long',
    'events_stages_current',
    'events_stages_history',
    'events_stages_history_long',
    'events_transactions_current',
    'events_transactions_history'
);

-- ============================================================================
-- Step 4: ENABLE WAIT INSTRUMENTS (mutex, rwlock, cond)
-- ============================================================================
SELECT '=== Enabling wait/synch instruments ===' AS section;

UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/synch/mutex/%';

UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/synch/rwlock/%';

UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/synch/cond/%';

-- ============================================================================
-- Step 5: ENABLE LOCK INSTRUMENTS
-- ============================================================================
SELECT '=== Enabling wait/lock instruments ===' AS section;

UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/lock/%';

-- ============================================================================
-- Step 6: ENABLE STAGE INSTRUMENTS (shows what threads are doing)
-- ============================================================================
SELECT '=== Enabling stage instruments ===' AS section;

UPDATE performance_schema.setup_instruments
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'stage/%';

-- ============================================================================
-- Step 7: Verify changes
-- ============================================================================
SELECT '=== AFTER: Instrumentation Summary ===' AS section;
SELECT
    CASE
        WHEN NAME LIKE 'wait/synch/mutex%' THEN 'wait/synch/mutex'
        WHEN NAME LIKE 'wait/synch/rwlock%' THEN 'wait/synch/rwlock'
        WHEN NAME LIKE 'wait/synch/cond%' THEN 'wait/synch/cond'
        WHEN NAME LIKE 'wait/lock%' THEN 'wait/lock'
        WHEN NAME LIKE 'wait/io%' THEN 'wait/io'
        WHEN NAME LIKE 'stage%' THEN 'stage'
        WHEN NAME LIKE 'statement%' THEN 'statement'
        WHEN NAME LIKE 'transaction%' THEN 'transaction'
        ELSE 'other'
    END AS instrument_family,
    SUM(ENABLED = 'YES') AS enabled_count,
    SUM(ENABLED = 'NO') AS disabled_count,
    COUNT(*) AS total
FROM performance_schema.setup_instruments
GROUP BY instrument_family
ORDER BY disabled_count DESC;

SELECT '=== AFTER: Consumer Status ===' AS section;
SELECT NAME, ENABLED FROM performance_schema.setup_consumers ORDER BY NAME;

-- ============================================================================
-- Step 8: Parameter group recommendations (for persistence across reboots)
-- ============================================================================
SELECT '=== PARAMETER GROUP SETTINGS (for persistence) ===' AS section;
SELECT 'Add these to your Aurora DB parameter group:' AS instructions
UNION ALL SELECT '  performance_schema = 1'
UNION ALL SELECT '  performance-schema-instrument = wait/%=ON'
UNION ALL SELECT '  performance-schema-consumer-events-waits-current = ON'
UNION ALL SELECT '  performance-schema-consumer-events-waits-history = ON'
UNION ALL SELECT '  performance-schema-consumer-events-stages-current = ON'
UNION ALL SELECT '  performance-schema-consumer-events-stages-history = ON'
UNION ALL SELECT ''
UNION ALL SELECT 'NOTE: parameter group changes to performance_schema require instance REBOOT.'
UNION ALL SELECT 'NOTE: Runtime changes (this script) take effect immediately but are lost on reboot.';

SELECT '=== Instrumentation setup complete ===' AS section;
