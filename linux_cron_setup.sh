#!/bin/bash
# ============================================================================
# Linux Cron Job Setup for Aurora MySQL Diagnostics
# Run this script to configure automated diagnostic collection
# ============================================================================
# Usage:
#   chmod +x linux_cron_setup.sh
#   ./linux_cron_setup.sh
# ============================================================================

set -e

echo "=============================================="
echo " Aurora MySQL Diagnostic - Cron Setup"
echo "=============================================="
echo ""

# Configuration - EDIT THESE VALUES
AURORA_HOST="${AURORA_HOST:-aurora8.cluster-xxxxx.region.rds.amazonaws.com}"
AURORA_USER="${AURORA_USER:-admin}"
AURORA_DB="${AURORA_DB:-qldwh}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/aurora-diagnostic}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/aurora_diagnostics_output}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

echo "Configuration:"
echo "  Aurora Host:    $AURORA_HOST"
echo "  Aurora User:    $AURORA_USER"
echo "  Aurora DB:      $AURORA_DB"
echo "  Install Dir:    $INSTALL_DIR"
echo "  Output Dir:     $OUTPUT_DIR"
echo "  Retention:      ${RETENTION_DAYS} days"
echo ""

# Create directories
mkdir -p "$OUTPUT_DIR/diagnostics"
mkdir -p "$OUTPUT_DIR/tests"
mkdir -p "$OUTPUT_DIR/logs"

# ============================================================================
# Create the diagnostic wrapper script
# ============================================================================
cat > "$INSTALL_DIR/scheduling/run_diagnostic.sh" << 'WRAPPER'
#!/bin/bash
# Scheduled Aurora MySQL Diagnostic Runner
# Called by cron - do not run interactively unless testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scheduling/config.env"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/diagnostics/diag_${TIMESTAMP}.txt"
LOG_FILE="$OUTPUT_DIR/logs/cron_history.log"

# Retention: delete old outputs
find "$OUTPUT_DIR/diagnostics" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null
find "$OUTPUT_DIR/tests" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null

# Run diagnostic
export MYSQL_PWD="$AURORA_PASS"
mysql -h "$AURORA_HOST" -u "$AURORA_USER" "$AURORA_DB" \
  < "$SCRIPT_DIR/diagnostics/aurora_mysql_diagnostic_locks_latches.sql" \
  > "$OUTPUT_FILE" 2>&1

EXIT_CODE=$?
echo "[${TIMESTAMP}] diagnostic exit=$EXIT_CODE output=$OUTPUT_FILE" >> "$LOG_FILE"

# Alert on errors (optional - uncomment to enable)
# if [ $EXIT_CODE -ne 0 ]; then
#   echo "Diagnostic failed at $TIMESTAMP" | mail -s "Aurora Diagnostic Alert" you@email.com
# fi

exit $EXIT_CODE
WRAPPER

chmod +x "$INSTALL_DIR/scheduling/run_diagnostic.sh"

# ============================================================================
# Create the lock contention test wrapper
# ============================================================================
cat > "$INSTALL_DIR/scheduling/run_lock_test.sh" << 'WRAPPER'
#!/bin/bash
# Scheduled Lock Contention Test Runner
# WARNING: This modifies data - only use on test environments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scheduling/config.env"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/logs/cron_history.log"

export MYSQL_PWD="$AURORA_PASS"
bash "$SCRIPT_DIR/tests/aurora_lock_contention_test.sh" \
  > "$OUTPUT_DIR/tests/lock_test_${TIMESTAMP}.log" 2>&1

EXIT_CODE=$?
echo "[${TIMESTAMP}] lock_test exit=$EXIT_CODE" >> "$LOG_FILE"

exit $EXIT_CODE
WRAPPER

chmod +x "$INSTALL_DIR/scheduling/run_lock_test.sh"

# ============================================================================
# Create configuration file (credentials stored here)
# ============================================================================
cat > "$INSTALL_DIR/scheduling/config.env" << CONFIG
# Aurora MySQL Diagnostic Configuration
# This file is sourced by wrapper scripts
# IMPORTANT: chmod 600 this file and add to .gitignore

AURORA_HOST="$AURORA_HOST"
AURORA_USER="$AURORA_USER"
AURORA_PASS="CHANGE_ME_TO_YOUR_PASSWORD"
AURORA_DB="$AURORA_DB"
OUTPUT_DIR="$OUTPUT_DIR"
RETENTION_DAYS=$RETENTION_DAYS
CONFIG

chmod 600 "$INSTALL_DIR/scheduling/config.env"

echo ""
echo "Files created:"
echo "  $INSTALL_DIR/scheduling/run_diagnostic.sh"
echo "  $INSTALL_DIR/scheduling/run_lock_test.sh"
echo "  $INSTALL_DIR/scheduling/config.env (chmod 600)"
echo ""

# ============================================================================
# Install cron jobs
# ============================================================================
echo "Choose a cron schedule:"
echo ""
echo "  1) Every 5 minutes  (active troubleshooting)"
echo "  2) Every 15 minutes (regular monitoring)"
echo "  3) Every hour       (baseline collection)"
echo "  4) Custom           (enter your own schedule)"
echo "  5) Skip             (I'll set up cron manually)"
echo ""
read -p "Select [1-5]: " CHOICE

case $CHOICE in
  1) CRON_SCHEDULE="*/5 * * * *" ;;
  2) CRON_SCHEDULE="*/15 * * * *" ;;
  3) CRON_SCHEDULE="0 * * * *" ;;
  4) read -p "Enter cron expression: " CRON_SCHEDULE ;;
  5) echo "Skipping cron setup. See instructions below."; CRON_SCHEDULE="" ;;
  *) echo "Invalid choice. Skipping."; CRON_SCHEDULE="" ;;
esac

if [ -n "$CRON_SCHEDULE" ]; then
  # Remove any existing aurora-diagnostic cron entries
  crontab -l 2>/dev/null | grep -v 'aurora-diagnostic' > /tmp/crontab_clean 2>/dev/null || true

  # Add new entry
  echo "$CRON_SCHEDULE $INSTALL_DIR/scheduling/run_diagnostic.sh # aurora-diagnostic" >> /tmp/crontab_clean

  crontab /tmp/crontab_clean
  rm /tmp/crontab_clean

  echo ""
  echo "Cron job installed:"
  echo "  $CRON_SCHEDULE $INSTALL_DIR/scheduling/run_diagnostic.sh"
  echo ""
  echo "Verify with: crontab -l"
fi

echo ""
echo "=============================================="
echo " Setup Complete"
echo "=============================================="
echo ""
echo "IMPORTANT: Edit the password in:"
echo "  $INSTALL_DIR/scheduling/config.env"
echo ""
echo "To manually add additional cron jobs:"
echo "  crontab -e"
echo ""
echo "Example cron entries:"
echo "  # Diagnostic every 15 min"
echo "  */15 * * * * $INSTALL_DIR/scheduling/run_diagnostic.sh"
echo ""
echo "  # Lock test weekly on Sunday 3 AM"
echo "  0 3 * * 0 $INSTALL_DIR/scheduling/run_lock_test.sh"
echo ""
echo "  # Diagnostic only during business hours (8-20 UTC, Mon-Fri)"
echo "  */15 8-20 * * 1-5 $INSTALL_DIR/scheduling/run_diagnostic.sh"
echo ""
echo "Monitor execution:"
echo "  tail -f $OUTPUT_DIR/logs/cron_history.log"
echo ""
