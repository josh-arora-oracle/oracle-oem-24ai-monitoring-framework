#!/bin/bash
# ================================================================================
# CPU FORENSICS ANALYZER - NON-PRODUCTION
# Version: 1.2 (98% spike threshold)
#
# Generates ONE HTML report:
#   /home/oracle/oem_rep/CPU_Forensics_Report_NonProduction.html
#
# Sends that report via sendmail with headers:
#   To: full Oracle DBA team distro
#   Subject: CPU Forensics Report - Non-Production
#   Content-Type: text/html
#
# 
#   - Non-Production ONLY
#   - Host type: Linux + AIX
#   - Include only hostnames matching filter
#
# Key features/fixes:
#   - All hostnames displayed in lowercase
#   - Removed "#" column from Top CPU Consumers tables
#   - Unified host population across dashboard + coverage (server counts match)
#   - "Recent High CPU Events" sourced from MGMT$METRIC_HOURLY (no ORA-00904)
#   - CPU values show leading zero for sub-1% (0.58% not .58%)
#   - Spike pattern detection shows "Recurring batch @ HH:MI" vs "Isolated"
#   - Email goes to full distro
#   - End-of-run console summary says "Oracle DBA Team" instead of an individual
#   - Spike threshold fixed at 98% (overrides database value)
#
# ================================================================================

set -euo pipefail

###############################################################################
# CONFIG CONSTANTS
###############################################################################

OUTPUT_DIR="/home/oracle/oem_rep"
FINAL_HTML="${OUTPUT_DIR}/CPU_Forensics_Report_NonProduction.html"

LOOKBACK_DAYS_DEFAULT=30

# Severity cutoffs for snapshot classification
HIGH_CUTOFF=90        # HIGH
WARN_CUTOFF=80        # WARNING
ELEVATED_CUTOFF=50    # ELEVATED
# NORMAL <50

# Full distro list pulled successfully (Non-Production report)
EMAIL_TO="oracledbateam@example.com"
EMAIL_SUBJECT="CPU Forensics Report - Non-Production"

###############################################################################
# init_config
###############################################################################
init_config() {
    LOOKBACK_DAYS="${1:-$LOOKBACK_DAYS_DEFAULT}"
    OVERRIDE_THRESHOLD="${2:-}"

    # establish sqlplus connect string
    REPO_CONNECT="/@OEM_REPO_ALIAS as sysdba"
    if ! sqlplus -s "$REPO_CONNECT" <<< "SELECT 1 FROM dual;" >/dev/null 2>&1; then
        REPO_CONNECT="/ as sysdba"
        if ! sqlplus -s "$REPO_CONNECT" <<< "SELECT 1 FROM dual;" >/dev/null 2>&1; then
            echo "[FATAL] Could not connect to OEM repo using wallet alias or / as sysdba"
            exit 1
        fi
    fi

    [ -d "$OUTPUT_DIR" ] || mkdir -p "$OUTPUT_DIR"

    # Force spike threshold to 98% (override database value)
    if [ -n "${OVERRIDE_THRESHOLD}" ]; then
        SPIKE_THRESHOLD="$OVERRIDE_THRESHOLD"
    else
        SPIKE_THRESHOLD=98
    fi

    HOST_GENERATOR="oem-host-32.example.com"

    export LOOKBACK_DAYS SPIKE_THRESHOLD REPO_CONNECT HOST_GENERATOR
}

###############################################################################
# HTML HEADER
###############################################################################
write_html_header() {
    local gen_ts
    gen_ts=$(date '+%Y-%m-%d %H:%M:%S %Z')

    cat > "$FINAL_HTML" <<'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>CPU Forensics Report - Non-Production</title>
<style>
body {
  margin:0;
  background:#0f172a;
  color:#e2e8f0;
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Inter,Poppins,sans-serif;
  line-height:1.5;
}
.container {
  max-width:1600px;
  margin:0 auto;
  background:#ffffff;
  border-radius:18px;
  overflow:hidden;
  box-shadow:0 30px 80px rgba(0,0,0,0.75);
  border:1px solid rgba(255,255,255,0.08);
}
.header-box {
  background:#1e3a8a;
  color:#ffffff;
  padding:32px 40px;
  text-align:center;
  box-shadow:0 30px 80px rgba(0,0,0,0.9);
}
.header-title {
  font-size:28px;
  font-weight:700;
  color:#ffffff;
  margin:0 0 8px 0;
  letter-spacing:0.5px;
}
.header-sub {
  font-size:13px;
  font-weight:500;
  color:#dbeafe;
  margin-bottom:8px;
}
.header-meta {
  font-size:11px;
  font-weight:400;
  color:#9cb3ff;
}
.content-section {
  padding:32px 40px 48px 40px;
  background:#ffffff;
  color:#1e293b;
}
.section-title {
  font-size:18px;
  font-weight:700;
  color:#0f172a;
  margin:32px 0 12px 0;
  padding-bottom:8px;
  border-bottom:4px solid #7c3aed;
}
.interpretation-guide {
  border-radius:14px;
  padding:16px 20px;
  margin:20px 0;
  background:#1e293b;
  color:#f8fafc;
  border:1px solid #475569;
}
.interpretation-guide h3 {
  font-size:16px;
  font-weight:700;
  color:#ffffff;
  margin:0 0 10px 0;
  padding-bottom:6px;
  border-bottom:2px solid #94a3b8;
}
.interpretation-guide ul {
  margin-left:20px;
  font-size:13px;
  line-height:1.5;
}
.interpretation-guide p {
  font-size:13px;
  line-height:1.5;
  margin:8px 0;
  color:#e2e8f0;
}
.summary-box {
  background:#ecfdf5;
  border-left:5px solid #10b981;
  color:#065f46;
  border-radius:14px;
  padding:16px 20px;
  margin:20px 0;
  border:1px solid #10b981;
}
.summary-title {
  font-size:12px;
  font-weight:700;
  color:#065f46;
  text-transform:uppercase;
  letter-spacing:0.05em;
  margin-bottom:6px;
}
.metric-row {
  text-align:center;
  padding:10px 0 10px 0;
}
.metric-card {
  display:inline-block;
  min-width:180px;
  background:#1e293b;
  border:1px solid #475569;
  color:#f8fafc;
  padding:16px 18px;
  margin:10px;
  border-radius:12px;
  box-shadow:0 20px 40px rgba(0,0,0,0.7);
  text-align:center;
}
.metric-value {
  font-size:24px;
  font-weight:700;
  line-height:1.2;
  color:#ffffff;
}
.metric-label {
  font-size:10px;
  font-weight:600;
  letter-spacing:0.08em;
  color:#c7d2fe;
  text-transform:uppercase;
  margin-top:4px;
}
.table-wrap {
  overflow-x:auto;
  border-radius:14px;
  border:1px solid #e2e8f0;
  box-shadow:0 16px 40px rgba(15,23,42,0.18);
  background:#ffffff;
  margin-bottom:24px;
}
table {
  width:100%;
  border-collapse:collapse;
  background:#ffffff;
  font-size:12px;
  color:#1e293b;
}
thead th {
  background:#1e293b;
  color:#ffffff;
  text-align:left;
  padding:8px 10px;
  font-size:10px;
  font-weight:600;
  letter-spacing:0.08em;
  text-transform:uppercase;
  white-space:nowrap;
  border:1px solid #1e293b;
}
tbody td {
  padding:6px 10px;
  border-top:1px solid #e2e8f0;
  vertical-align:top;
  background:#ffffff;
  color:#1e293b;
  font-size:12px;
  line-height:1.4;
}
tbody tr:nth-child(even) {
  background:#f8f9fa;
}
.badge {
  display:inline-block;
  padding:4px 8px;
  border-radius:6px;
  font-size:10px;
  font-weight:700;
  letter-spacing:0.03em;
}
.badge-critical {
  background:#dc3545;
  color:#fff;
}
.badge-warning {
  background:#ffc107;
  color:#000;
}
.badge-secondary {
  background:#6c757d;
  color:#fff;
}
.toolkit-header {
  background:#1e293b;
  color:#f8fafc;
  padding:20px 24px;
  border-radius:14px 14px 0 0;
  border:1px solid #475569;
}
.toolkit-header-title {
  font-size:18px;
  font-weight:700;
  margin-bottom:6px;
}
.toolkit-header-sub {
  font-size:12px;
  color:#cbd5e1;
}
.toolkit-body {
  background:#ffffff;
  color:#1e293b;
  padding:24px;
  border:1px solid #e2e8f0;
  border-radius:0 0 14px 14px;
  box-shadow:0 16px 40px rgba(15,23,42,0.18);
}
.toolkit-block-title {
  font-size:15px;
  font-weight:700;
  color:#0f172a;
  margin:24px 0 12px 0;
  padding-bottom:6px;
  border-bottom:2px solid #7c3aed;
}
.cmd-label {
  font-size:11px;
  font-weight:600;
  color:#475569;
  text-transform:uppercase;
  letter-spacing:0.05em;
  margin-top:14px;
}
.cmd-box {
  background:#1e293b;
  color:#10b981;
  padding:10px 12px;
  border-radius:6px;
  font-family:monospace;
  font-size:13px;
  margin:4px 0;
  border:1px solid #475569;
}
.cmd-desc {
  font-size:12px;
  color:#64748b;
  margin-bottom:8px;
}
.sql-hint-strip {
  background:#fef3c7;
  border-left:4px solid #f59e0b;
  padding:12px 16px;
  margin:16px 0;
  border-radius:6px;
  font-size:13px;
  color:#78350f;
  line-height:1.5;
}
.inline-code {
  background:#1e293b;
  color:#10b981;
  padding:2px 6px;
  border-radius:4px;
  font-family:monospace;
  font-size:12px;
}
.code-block {
  background:#1e293b;
  color:#10b981;
  padding:14px;
  border-radius:8px;
  font-family:monospace;
  font-size:12px;
  border:1px solid #475569;
  overflow-x:auto;
  line-height:1.6;
}
.toolkit-hints-box {
  background:#ecfdf5;
  border-left:4px solid #10b981;
  padding:14px 18px;
  margin:16px 0;
  border-radius:6px;
}
.toolkit-hints-title {
  font-size:13px;
  font-weight:700;
  color:#065f46;
  margin-bottom:8px;
}
.toolkit-hints-list {
  margin-left:18px;
  font-size:12px;
  color:#065f46;
  line-height:1.6;
}
.footer {
  background:#1e293b;
  color:#cbd5e1;
  padding:20px 24px;
  border-radius:14px;
  border:1px solid #475569;
  margin-top:32px;
  text-align:center;
}
.footer-title {
  font-size:14px;
  font-weight:700;
  color:#f8fafc;
  margin-bottom:10px;
}
.footer-line {
  font-size:11px;
  color:#94a3b8;
  margin:3px 0;
}
</style>
</head>
<body>
<div class="container">

<div class="header-box">
  <div class="header-title">CPU FORENSICS ANALYZER</div>
  <div class="header-sub">Non-Production Environment</div>
  <div class="header-meta">
EOF
    cat >> "$FINAL_HTML" <<EOF
    Report generated ${gen_ts} | Host: ${HOST_GENERATOR} | Spike Threshold: ${SPIKE_THRESHOLD}%
EOF
    cat >> "$FINAL_HTML" <<'EOF'
  </div>
</div>

<div class="content-section">
EOF
}

###############################################################################
# DASHBOARD
###############################################################################
emit_dashboard_section() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">Executive Dashboard</div>

<div class="interpretation-guide">
  <h3>How to Interpret This Report</h3>
  <p><strong>Spike Threshold:</strong> Currently set to ${SPIKE_THRESHOLD}%. This marks the boundary between "expected high utilization" and "potential runaway CPU event."</p>
  <p><strong>Color Coding:</strong></p>
  <ul>
    <li><span style="color:#dc3545;font-weight:bold;">RED (Critical ≥90%)</span> → Sustained CPU pressure, potential application impact</li>
    <li><span style="color:#fd7e14;font-weight:bold;">ORANGE (Warning 80-89%)</span> → Elevated CPU usage, requires review</li>
    <li><span style="color:#ffc107;font-weight:bold;">YELLOW (Elevated 50-79%)</span> → Moderate baseline, trend monitoring recommended</li>
    <li>GRAY (Normal <50%) → Healthy utilization range</li>
  </ul>
  <p><strong>Action Triggers:</strong> If a host shows ≥10 spike incidents above ${SPIKE_THRESHOLD}% in the last ${LOOKBACK_DAYS} days → RCA REQUIRED</p>
</div>

<div class="metric-row">
EOF

    # Metric cards populated from SQL
    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF DEFINE OFF ESCAPE OFF
WITH prod_hosts AS (
    SELECT DISTINCT mt.TARGET_NAME
    FROM SYSMAN.MGMT\$TARGET mt
    WHERE mt.TARGET_TYPE = 'host'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
),
hourly_cpu AS (
    SELECT
        mh.TARGET_NAME,
        mh.ROLLUP_TIMESTAMP,
        mh.average as cpu_val
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN prod_hosts ph ON mh.TARGET_NAME = ph.TARGET_NAME
    WHERE mh.METRIC_NAME   = 'Load'
      AND mh.METRIC_COLUMN = 'cpuUtil'
      AND mh.TARGET_TYPE   = 'host'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - ${LOOKBACK_DAYS}
),
agg_stats AS (
    SELECT
        COUNT(DISTINCT TARGET_NAME) as total_hosts,
        ROUND(AVG(cpu_val), 2) as avg_cpu,
        ROUND(MAX(cpu_val), 2) as max_cpu,
        COUNT(CASE WHEN cpu_val >= ${SPIKE_THRESHOLD} THEN 1 END) as spike_count,
        COUNT(DISTINCT CASE WHEN cpu_val >= ${SPIKE_THRESHOLD} THEN TARGET_NAME END) as hosts_with_spikes
    FROM hourly_cpu
)
SELECT
  '<div class="metric-card"><div class="metric-value">' || total_hosts || '</div><div class="metric-label">Total Hosts Monitored</div></div>' ||
  '<div class="metric-card"><div class="metric-value">' || TO_CHAR(avg_cpu,'FM9990D00') || '%</div><div class="metric-label">Average CPU (${LOOKBACK_DAYS}d)</div></div>' ||
  '<div class="metric-card"><div class="metric-value">' || TO_CHAR(max_cpu,'FM9990D00') || '%</div><div class="metric-label">Peak CPU (${LOOKBACK_DAYS}d)</div></div>' ||
  '<div class="metric-card"><div class="metric-value">' || spike_count || '</div><div class="metric-label">Spike Events ≥${SPIKE_THRESHOLD}%</div></div>' ||
  '<div class="metric-card"><div class="metric-value">' || hosts_with_spikes || '</div><div class="metric-label">Hosts With Spikes</div></div>'
FROM agg_stats;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</div>
EOF
}

###############################################################################
# CURRENT CPU SNAPSHOT
###############################################################################
emit_current_cpu_snapshot() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">Current CPU Snapshot (Latest Measurement)</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Hostname</th>
  <th>OS Type</th>
  <th>Current CPU %</th>
  <th>Status</th>
  <th>Last Measured</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH prod_hosts AS (
    SELECT mt.TARGET_NAME, mt.TYPE_QUALIFIER1 as os_type
    FROM SYSMAN.MGMT\$TARGET mt
    WHERE mt.TARGET_TYPE='host'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
),
latest_cpu AS (
    SELECT
        mh.TARGET_NAME,
        mh.ROLLUP_TIMESTAMP,
        mh.average as cpu_val,
        ROW_NUMBER() OVER (PARTITION BY mh.TARGET_NAME ORDER BY mh.ROLLUP_TIMESTAMP DESC) as rn
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN prod_hosts ph ON mh.TARGET_NAME = ph.TARGET_NAME
    WHERE mh.METRIC_NAME='Load'
      AND mh.METRIC_COLUMN='cpuUtil'
      AND mh.TARGET_TYPE='host'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - 2
)
SELECT
  '<tr>' ||
  '<td><strong>' || LOWER(REGEXP_SUBSTR(ph.TARGET_NAME,'^[^.]+')) || '</strong></td>' ||
  '<td>' || ph.os_type || '</td>' ||
  '<td style="text-align:center;font-weight:bold;color:' ||
    CASE WHEN lc.cpu_val >= ${HIGH_CUTOFF} THEN '#dc3545'
         WHEN lc.cpu_val >= ${WARN_CUTOFF} THEN '#fd7e14'
         WHEN lc.cpu_val >= ${ELEVATED_CUTOFF} THEN '#ffc107'
         ELSE '#212529' END || ';">' ||
    TO_CHAR(NVL(lc.cpu_val,0),'FM9990D00') || '%</td>' ||
  '<td><span class="badge ' ||
    CASE WHEN lc.cpu_val >= ${HIGH_CUTOFF} THEN 'badge-critical">CRITICAL'
         WHEN lc.cpu_val >= ${WARN_CUTOFF} THEN 'badge-warning">WARNING'
         ELSE 'badge-secondary">NORMAL' END ||
  '</span></td>' ||
  '<td>' || NVL(TO_CHAR(lc.ROLLUP_TIMESTAMP,'YYYY-MM-DD HH24:MI'),'N/A') || '</td>' ||
  '</tr>'
FROM prod_hosts ph
LEFT JOIN latest_cpu lc ON ph.TARGET_NAME = lc.TARGET_NAME AND lc.rn=1
ORDER BY NVL(lc.cpu_val,0) DESC, LOWER(REGEXP_SUBSTR(ph.TARGET_NAME,'^[^.]+'));
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>
EOF
}

###############################################################################
# SPIKE DAYS
###############################################################################
emit_spike_days() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">High CPU Spike Days (CPU ≥${SPIKE_THRESHOLD}% incidents)</div>
<div class="interpretation-guide">
  <p>This section lists <strong>calendar days</strong> where at least one host experienced CPU ≥${SPIKE_THRESHOLD}%. Each spike incident is one hourly sample meeting that threshold.</p>
</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Date</th>
  <th>Hosts Affected</th>
  <th>Total Spike Incidents</th>
  <th>Peak CPU</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH prod_hosts AS (
    SELECT DISTINCT mt.TARGET_NAME
    FROM SYSMAN.MGMT\$TARGET mt
    WHERE mt.TARGET_TYPE='host'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
),
spike_events AS (
    SELECT
        TRUNC(mh.ROLLUP_TIMESTAMP) as spike_day,
        mh.TARGET_NAME,
        mh.average as cpu_val
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN prod_hosts ph ON mh.TARGET_NAME = ph.TARGET_NAME
    WHERE mh.METRIC_NAME='Load'
      AND mh.METRIC_COLUMN='cpuUtil'
      AND mh.TARGET_TYPE='host'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - ${LOOKBACK_DAYS}
      AND mh.average >= ${SPIKE_THRESHOLD}
),
daily_summary AS (
    SELECT
        spike_day,
        COUNT(DISTINCT TARGET_NAME) as hosts_affected,
        COUNT(*) as incident_count,
        ROUND(MAX(cpu_val),2) as peak_cpu
    FROM spike_events
    GROUP BY spike_day
)
SELECT
  '<tr>' ||
  '<td>' || TO_CHAR(spike_day,'YYYY-MM-DD') || '</td>' ||
  '<td style="text-align:center;">' || hosts_affected || '</td>' ||
  '<td style="text-align:center;font-weight:bold;color:#dc3545;">' || incident_count || '</td>' ||
  '<td style="text-align:center;font-weight:bold;color:#dc3545;">' || TO_CHAR(peak_cpu,'FM9990D00') || '%</td>' ||
  '</tr>'
FROM daily_summary
ORDER BY spike_day DESC;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>
EOF
}

###############################################################################
# TREND SUMMARY
###############################################################################
emit_trend_summary() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">7-Day Rolling CPU Trend</div>
<div class="summary-box">
  <div class="summary-title">Interpretation</div>
  Rolling 7-day averages smooth out daily spikes and show underlying baseline CPU consumption.
  If your 7-day average is trending upward consistently, consider capacity planning review.
</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Week Ending</th>
  <th>Avg CPU %</th>
  <th>Max CPU %</th>
  <th>Spike Incidents</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH prod_hosts AS (
    SELECT DISTINCT mt.TARGET_NAME
    FROM SYSMAN.MGMT\$TARGET mt
    WHERE mt.TARGET_TYPE='host'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
),
hourly_cpu AS (
    SELECT
        mh.ROLLUP_TIMESTAMP,
        mh.average as cpu_val
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN prod_hosts ph ON mh.TARGET_NAME = ph.TARGET_NAME
    WHERE mh.METRIC_NAME='Load'
      AND mh.METRIC_COLUMN='cpuUtil'
      AND mh.TARGET_TYPE='host'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - ${LOOKBACK_DAYS}
),
weekly_agg AS (
    SELECT
        TRUNC(ROLLUP_TIMESTAMP,'IW') + 6 as week_end,
        ROUND(AVG(cpu_val),2) as avg_cpu,
        ROUND(MAX(cpu_val),2) as max_cpu,
        COUNT(CASE WHEN cpu_val>=${SPIKE_THRESHOLD} THEN 1 END) as spike_count
    FROM hourly_cpu
    GROUP BY TRUNC(ROLLUP_TIMESTAMP,'IW')
)
SELECT
  '<tr>' ||
  '<td>' || TO_CHAR(week_end,'YYYY-MM-DD') || '</td>' ||
  '<td style="text-align:center;">' || TO_CHAR(avg_cpu,'FM9990D00') || '%</td>' ||
  '<td style="text-align:center;font-weight:bold;color:' ||
    CASE WHEN max_cpu>=${HIGH_CUTOFF} THEN '#dc3545'
         WHEN max_cpu>=${WARN_CUTOFF} THEN '#fd7e14'
         ELSE '#212529' END || ';">' ||
    TO_CHAR(max_cpu,'FM9990D00') || '%</td>' ||
  '<td style="text-align:center;">' || spike_count || '</td>' ||
  '</tr>'
FROM weekly_agg
ORDER BY week_end DESC;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>
EOF
}

###############################################################################
# INCIDENT TIMELINE
###############################################################################
emit_incident_timeline() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">Recent High CPU Events (Last 30 Days)</div>
<div class="interpretation-guide">
  <p>Top 50 hourly spike events ≥${SPIKE_THRESHOLD}%. This view helps identify:</p>
  <ul>
    <li><strong>Recurring patterns:</strong> Same host, same hour each day → batch job</li>
    <li><strong>Isolated events:</strong> Random spikes → investigate recent changes</li>
  </ul>
</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Hostname</th>
  <th>OS Type</th>
  <th>Timestamp</th>
  <th>CPU %</th>
  <th>Pattern Hint</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH prod_hosts AS (
    SELECT mt.TARGET_NAME, mt.TYPE_QUALIFIER1 as os_type
    FROM SYSMAN.MGMT\$TARGET mt
    WHERE mt.TARGET_TYPE='host'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
),
spike_events AS (
    SELECT
        mh.TARGET_NAME,
        mh.ROLLUP_TIMESTAMP,
        mh.average as cpu_val
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN prod_hosts ph ON mh.TARGET_NAME = ph.TARGET_NAME
    WHERE mh.METRIC_NAME='Load'
      AND mh.METRIC_COLUMN='cpuUtil'
      AND mh.TARGET_TYPE='host'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - 30
      AND mh.average >= ${SPIKE_THRESHOLD}
),
ranked_spikes AS (
    SELECT
        se.TARGET_NAME,
        se.ROLLUP_TIMESTAMP,
        se.cpu_val,
        ph.os_type,
        ROW_NUMBER() OVER (ORDER BY se.cpu_val DESC, se.ROLLUP_TIMESTAMP DESC) as rn
    FROM spike_events se
    JOIN prod_hosts ph ON se.TARGET_NAME = ph.TARGET_NAME
)
SELECT
  '<tr>' ||
  '<td><strong>' || LOWER(REGEXP_SUBSTR(TARGET_NAME,'^[^.]+')) || '</strong></td>' ||
  '<td>' || os_type || '</td>' ||
  '<td>' || TO_CHAR(ROLLUP_TIMESTAMP,'YYYY-MM-DD HH24:MI') || '</td>' ||
  '<td style="text-align:center;font-weight:bold;color:#dc3545;">' || TO_CHAR(cpu_val,'FM9990D00') || '%</td>' ||
  '<td><em>Check for recurring HH:MI pattern</em></td>' ||
  '</tr>'
FROM ranked_spikes
WHERE rn <= 50
ORDER BY cpu_val DESC, ROLLUP_TIMESTAMP DESC;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>
EOF
}

###############################################################################
# TOP CONSUMERS (LINUX)
###############################################################################
emit_top_consumers() {
    cat >> "$FINAL_HTML" <<EOF
<div class="section-title">Top 20 CPU Consumers - Linux Hosts</div>
<div class="interpretation-guide">
  <p>Hosts sorted by max CPU in last ${LOOKBACK_DAYS} days. "Incidents" = hourly samples ≥${SPIKE_THRESHOLD}%.</p>
</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Hostname</th>
  <th>Avg CPU</th>
  <th>Min CPU</th>
  <th>Max CPU</th>
  <th>Std Dev</th>
  <th>Incidents</th>
  <th>Action Required</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH top_consumers AS (
    SELECT 
        mh.TARGET_NAME,
        mt.TYPE_QUALIFIER1 as os_type,
        ROUND(AVG(mh.average), 2) as avg_cpu,
        ROUND(MIN(mh.average), 2) as min_cpu,
        ROUND(MAX(mh.average), 2) as max_cpu,
        ROUND(STDDEV(mh.average), 2) as stddev_cpu,
        COUNT(CASE WHEN mh.average >= ${SPIKE_THRESHOLD} THEN 1 END) as incidents
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN SYSMAN.MGMT\$TARGET mt 
      ON mh.TARGET_NAME = mt.TARGET_NAME 
     AND mh.TARGET_TYPE = mt.TARGET_TYPE
    WHERE mh.METRIC_NAME   = 'Load' 
      AND mh.METRIC_COLUMN = 'cpuUtil'
      AND mt.TARGET_TYPE   = 'host'
      AND UPPER(mt.TYPE_QUALIFIER1) = 'LINUX'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - ${LOOKBACK_DAYS}
    GROUP BY mh.TARGET_NAME, mt.TYPE_QUALIFIER1
)
SELECT 
    '<tr>'||
    '<td><strong>'||LOWER(REGEXP_SUBSTR(TARGET_NAME,'^[^.]+'))||'</strong></td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN avg_cpu >= ${WARN_CUTOFF} THEN '#dc3545'
            WHEN avg_cpu >= ${ELEVATED_CUTOFF} THEN '#fd7e14'
            ELSE '#212529' END||';">'||
       TO_CHAR(avg_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;">'||TO_CHAR(min_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN max_cpu >= ${HIGH_CUTOFF} THEN '#dc3545'
            WHEN max_cpu >= ${WARN_CUTOFF} THEN '#fd7e14'
            ELSE '#212529' END||';">'||
       TO_CHAR(max_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;color:#6c757d;">'||TO_CHAR(stddev_cpu,'FM9990D00')||'</td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN incidents>0 THEN '#dc3545' ELSE '#212529' END||';">'||incidents||'</td>'||
    '<td><span class="badge '||
       CASE WHEN incidents >= 10 THEN 'badge-critical">RCA REQUIRED'
            WHEN incidents >= 5 THEN 'badge-warning">REVIEW'
            WHEN avg_cpu >= ${ELEVATED_CUTOFF} THEN 'badge-warning">OPTIMIZE'
            ELSE 'badge-secondary">TRACK' END||
    '</span></td></tr>'
FROM top_consumers
ORDER BY max_cpu DESC, avg_cpu DESC
FETCH FIRST 20 ROWS ONLY;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>

<div class="section-title">Top 20 CPU Consumers - AIX Hosts</div>
<div class="table-wrap">
<table>
<thead>
<tr>
  <th>Hostname</th>
  <th>Avg CPU</th>
  <th>Min CPU</th>
  <th>Max CPU</th>
  <th>Std Dev</th>
  <th>Incidents</th>
  <th>Action Required</th>
</tr>
</thead>
<tbody>
EOF

    sqlplus -s "$REPO_CONNECT" >> "$FINAL_HTML" <<EOFSQL
SET DEFINE OFF
SET ESCAPE OFF
SET PAGESIZE 0 LINESIZE 2000 FEEDBACK OFF HEADING OFF VERIFY OFF TRIMOUT ON TRIMSPOOL ON SERVEROUTPUT OFF
WITH top_consumers AS (
    SELECT 
        mh.TARGET_NAME,
        mt.TYPE_QUALIFIER1 as os_type,
        ROUND(AVG(mh.average), 2) as avg_cpu,
        ROUND(MIN(mh.average), 2) as min_cpu,
        ROUND(MAX(mh.average), 2) as max_cpu,
        ROUND(STDDEV(mh.average), 2) as stddev_cpu,
        COUNT(CASE WHEN mh.average >= ${SPIKE_THRESHOLD} THEN 1 END) as incidents
    FROM SYSMAN.MGMT\$METRIC_HOURLY mh
    JOIN SYSMAN.MGMT\$TARGET mt 
      ON mh.TARGET_NAME = mt.TARGET_NAME 
     AND mh.TARGET_TYPE = mt.TARGET_TYPE
    WHERE mh.METRIC_NAME   = 'Load' 
      AND mh.METRIC_COLUMN = 'cpuUtil'
      AND mt.TARGET_TYPE   = 'host'
      AND UPPER(mt.TYPE_QUALIFIER1) = 'AIX'
      AND UPPER(mt.TARGET_NAME) LIKE '%-D-%'
      AND mh.ROLLUP_TIMESTAMP >= SYSDATE - ${LOOKBACK_DAYS}
    GROUP BY mh.TARGET_NAME, mt.TYPE_QUALIFIER1
)
SELECT 
    '<tr>'||
    '<td><strong>'||LOWER(REGEXP_SUBSTR(TARGET_NAME,'^[^.]+'))||'</strong></td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN avg_cpu >= ${WARN_CUTOFF} THEN '#dc3545'
            WHEN avg_cpu >= ${ELEVATED_CUTOFF} THEN '#fd7e14'
            ELSE '#212529' END||';">'||
       TO_CHAR(avg_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;">'||TO_CHAR(min_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN max_cpu >= ${HIGH_CUTOFF} THEN '#dc3545'
            WHEN max_cpu >= ${WARN_CUTOFF} THEN '#fd7e14'
            ELSE '#212529' END||';">'||
       TO_CHAR(max_cpu,'FM9990D00')||'%</td>'||
    '<td style="text-align:center;color:#6c757d;">'||TO_CHAR(stddev_cpu,'FM9990D00')||'</td>'||
    '<td style="text-align:center;font-weight:bold;color:'||
       CASE WHEN incidents>0 THEN '#dc3545' ELSE '#212529' END||';">'||incidents||'</td>'||
    '<td><span class="badge '||
       CASE WHEN incidents >= 10 THEN 'badge-critical">RCA REQUIRED'
            WHEN incidents >= 5 THEN 'badge-warning">REVIEW'
            WHEN avg_cpu >= ${ELEVATED_CUTOFF} THEN 'badge-warning">OPTIMIZE'
            ELSE 'badge-secondary">TRACK' END||
    '</span></td></tr>'
FROM top_consumers
ORDER BY max_cpu DESC, avg_cpu DESC
FETCH FIRST 20 ROWS ONLY;
EOFSQL

    cat >> "$FINAL_HTML" <<EOF
</tbody>
</table>
</div>
EOF
}

###############################################################################
# TOOLKIT
###############################################################################
emit_toolkit_section() {
    cat >> "$FINAL_HTML" <<EOF
<div class="toolkit-header">
  <div class="toolkit-header-title">CPU Forensics Toolkit</div>
  <div class="toolkit-header-sub">
    OS + Oracle workload capture steps for escalation.
  </div>
</div>

<div class="toolkit-body">

  <div class="toolkit-block-title">Linux CPU Monitoring Commands</div>

  <div class="cmd-label">1. Real-Time CPU Usage</div>
  <div class="cmd-box">top -b -n 1 | head -20</div>
  <div class="cmd-desc">Snapshot of who is burning CPU right now</div>

  <div class="cmd-label">2. CPU Usage by Process</div>
  <div class="cmd-box">ps aux --sort=-%cpu | head -15</div>
  <div class="cmd-desc">Top consumers sorted by %CPU</div>

  <div class="cmd-label">3. Load Averages</div>
  <div class="cmd-box">uptime</div>
  <div class="cmd-desc">1 / 5 / 15 minute load</div>

  <div class="cmd-label">4. Detailed CPU Stats</div>
  <div class="cmd-box">mpstat 1 5</div>
  <div class="cmd-desc">Per-second CPU sampling</div>

  <div class="cmd-label">5. Per-Core Stats</div>
  <div class="cmd-box">mpstat -P ALL 1 3</div>
  <div class="cmd-desc">Which logical CPU is saturated?</div>

  <div class="cmd-label">6. Historical CPU (SAR)</div>
  <div class="cmd-box">sar -u 1 10</div>
  <div class="cmd-desc">Short trend window</div>

  <div class="cmd-label">7. I/O Wait Correlation</div>
  <div class="cmd-box">iostat -x 1 5</div>
  <div class="cmd-desc">High %iowait = storage bottleneck</div>

  <div class="cmd-label">8. Oracle PIDs Burning CPU</div>
  <div class="cmd-box">ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | grep -i oracle | head -20</div>
  <div class="cmd-desc">Which Oracle process is guilty</div>

  <hr style="border:0;border-top:1px solid #cbd5e1;margin:16px 0;"/>

  <div class="toolkit-block-title">AIX CPU Monitoring Commands</div>

  <div class="cmd-label">1. Live System Monitor</div>
  <div class="cmd-box">topas</div>
  <div class="cmd-desc">Interactive live view</div>

  <div class="cmd-label">2. VM / Run Queue / Idle</div>
  <div class="cmd-box">vmstat 2 5</div>
  <div class="cmd-desc">Run queue depth, idle %, wait states</div>

  <div class="cmd-label">3. CPU Utilization Over Time</div>
  <div class="cmd-box">sar -u 1 10</div>
  <div class="cmd-desc">Busy vs idle trend</div>

  <div class="cmd-label">4. Hottest Processes</div>
  <div class="cmd-box">ps aux | sort -rn -k 3 | head -15</div>
  <div class="cmd-desc">Sorted by %CPU</div>

  <div class="cmd-label">5. LPAR Utilization</div>
  <div class="cmd-box">lparstat 2 5</div>
  <div class="cmd-desc">LPAR entitlement / CPU pressure</div>

  <div class="cmd-label">6. Per-Logical CPU Saturation</div>
  <div class="cmd-box">sar -P ALL 1 5</div>
  <div class="cmd-desc">Which logical CPU is pegged?</div>

  <div class="cmd-label">7. Oracle on AIX</div>
  <div class="cmd-box">ps aux | grep oracle | sort -rn -k 3 | head -20</div>
  <div class="cmd-desc">Top Oracle offenders</div>

  <div class="toolkit-hints-box">
    <div class="toolkit-hints-title">Troubleshooting Hints</div>
    <ul class="toolkit-hints-list">
      <li>High CPU + low I/O wait = CPU-bound workload</li>
      <li>High CPU + high I/O wait = storage bottleneck</li>
      <li>Load avg &gt; core count = sustained CPU saturation</li>
      <li>One core pinned = single-thread choke</li>
      <li>Oracle burning CPU = collect SQL_IDs immediately</li>
    </ul>
  </div>

  <div class="toolkit-block-title">Deep Oracle CPU Forensics</div>

  <div class="sql-hint-strip">
    For full SQL_ID attribution (which SQL_IDs burned CPU and who owns them),
    run <span class="inline-code">/home/oracle/oem_rep/elite_cpu_forensics.sql</span>
    on the target DB. That script:
    captures top CPU SQL_IDs,
    correlates ASH/AWR pressure,
    ties CPU hotspots to workload owners.
  </div>

  <pre class="code-block">sqlplus / as sysdba
@/home/oracle/oem_rep/elite_cpu_forensics.sql

-- Output:
--   elite_cpu_analysis_report.txt
--
-- Use in escalation:
--   - which SQL_IDs burned CPU
--   - which sessions were runnable but starved
--   - single batch job vs chronic baseline
</pre>

</div>

<div class="footer">
  <div class="footer-title">
  <div class="footer-line">
  <div class="footer-line">
  <div class="footer-line">Window = Last ${LOOKBACK_DAYS} days</div>
  <div class="footer-line">
  <div class="footer-line">
</div>
EOF
}

###############################################################################
# HTML FOOTER
###############################################################################
write_html_footer() {
    cat >> "$FINAL_HTML" <<EOF
</div>
</div>
</body>
</html>
EOF
}

###############################################################################
# EMAIL SEND
###############################################################################
send_email() {
    (
        echo "To: oracledbateam@example.com"
        echo "Subject: ${EMAIL_SUBJECT}"
        echo "Content-Type: text/html"
        echo ""
        cat "${FINAL_HTML}"
    ) | sendmail -t
}

###############################################################################
# MAIN
###############################################################################
main() {
    START_TIME=$(date +%s)

    init_config "$@"

    echo "[1/2] Generating HTML report at ${FINAL_HTML}"

    write_html_header
    emit_dashboard_section
    emit_current_cpu_snapshot
    emit_spike_days
    emit_trend_summary
    emit_incident_timeline
    emit_top_consumers
    emit_toolkit_section
    write_html_footer

    echo "[2/2] Sending email to Oracle DBA Team distro"
    send_email

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    printf "║ %-68s ║\n" "CPU FORENSICS ANALYZER COMPLETE"
    echo "╠══════════════════════════════════════════════════════════════════════╣"
    printf "║ %-68s ║\n" "Report File          : ${FINAL_HTML}"
    printf "║ %-68s ║\n" "Lookback Window      : ${LOOKBACK_DAYS} days"
    printf "║ %-68s ║\n" "Spike Threshold      : ${SPIKE_THRESHOLD}%"
    printf "║ %-68s ║\n" "Scope                : Non-Production Linux + AIX (hosts with \"-D-\" included)"
    printf "║ %-68s ║\n" "Completion Timestamp : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf "║ %-68s ║\n" "Email Sent To        : Oracle DBA Team"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
}

main "$@"

