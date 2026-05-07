# Disclaimer & Safety Information

## For AWS Customers

This toolkit is an **open-source community project** and is NOT an official AWS product or endorsed by AWS.

### Before using in your environment:

1. **Start with Performance Insights** — it's included free with Aurora and provides safe, non-invasive monitoring without running any queries against your database.

2. **The diagnostic scripts (`diagnostics/`) are read-only** — they use only `SELECT`, `SHOW`, and reads from `performance_schema` / `information_schema`. They are safe for production use.

3. **The instrumentation script (`enable_instrumentation.sql`) modifies performance_schema runtime state** — this adds monitoring overhead (~5-10% CPU). Changes revert on instance reboot. Safe for R-class instances; DO NOT run on T-class instances.

4. **The test scripts (`tests/`) are DESTRUCTIVE** — they CREATE/DROP tables, INSERT/UPDATE/DELETE data, and intentionally cause deadlocks and lock contention. NEVER run on production. They include a safety gate requiring explicit confirmation.

### Risk Classification

| Script | Risk Level | Modifies Data | Safe for Production |
|--------|-----------|---------------|---------------------|
| `diagnostics/aurora_mysql_diagnostic_locks_latches.sql` | None | No | **Yes** |
| `diagnostics/mysql_diagnostic_locks_latches.sql` | None | No | **Yes** |
| `diagnostics/generate_html_report.sh` | None | No | **Yes** |
| `diagnostics/enable_instrumentation.sql` | Low | performance_schema only | **Yes** (R-class only) |
| `tests/aurora_test_setup.sql` | **High** | DROPS database | **No** |
| `tests/aurora_lock_contention_test.sh` | **High** | DML + deadlocks | **No** |
| `tests/aurora_parallel_test.sh` | None | No (SELECT only) | **Yes** |

### AWS Shared Responsibility

- **You are responsible** for determining whether these scripts are appropriate for your environment, compliance requirements, and security policies.
- **Test in non-production** before using any script in production.
- **Review scripts before execution** — read the SQL/bash before running it against your databases.
- **Credential management** — use IAM database authentication or AWS Secrets Manager. Do not hardcode credentials.

### No Warranty

This software is provided "as is", without warranty of any kind. The authors are not responsible for any data loss, outages, or other damages resulting from its use. See the LICENSE file for full terms.
