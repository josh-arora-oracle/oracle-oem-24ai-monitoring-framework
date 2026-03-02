#!/bin/bash

# Configuration variables
init_config() {
    # Try multiple connection methods for robustness (NonProd first, then local)
    REPO_CONNECT="/@OEM_REPO_ALIAS as sysdba"
    
    # Test connection before proceeding
    if ! sqlplus -s "$REPO_CONNECT" <<< "SELECT 1 FROM dual;" >/dev/null 2>&1; then
        echo "WARNING: Primary connection failed, trying alternative..."
        REPO_CONNECT="/ as sysdba"
        if ! sqlplus -s "$REPO_CONNECT" <<< "SELECT 1 FROM dual;" >/dev/null 2>&1; then
            echo "ERROR: Cannot connect to Oracle database. Please check:"
            echo "1. TNS alias 'OEM_REPO_ALIAS' exists and is valid"
            echo "2. Oracle wallet is configured correctly"
            echo "3. User has SYSDBA privileges"
            echo "4. Database is accessible"
            exit 1
        fi
    fi

    OUTPUT_DIR="/home/oracle/oem_rep"
    HeathCheck_Report_File="HealthCheck_Report_${1}.html"
    
    # Check if OUTPUT_DIR exists, exit if not
    if [ ! -d "$OUTPUT_DIR" ]; then
        echo "ERROR: Directory $OUTPUT_DIR does not exist. Please create it first."
        exit 1
    fi
}

# Create HTML header with styles
create_html_header() {
    cat <<EOF > "$OUTPUT_DIR/HealthCheck_Report_head"
<!DOCTYPE html>
<html>
<head>
    <title>Health check report for Non-Prod OEM 24ai $1</title>
    <style>
        body {
            font-family: Arial, sans-serif;
        }
        .table-container {
            max-width: 80%; /* Ensures table fits the screen width */
            overflow-x: auto; /* Adds horizontal scrolling for wide tables */
        }
        table {
            border-collapse: collapse;
            border: 2px solid black;
            margin: auto;
        }
        th, td {
            border: 2px solid black;
            padding: 5px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        tr.low {
            background-color: white; /* White */
        }
        tr.warning {
            background-color: #e0ff33; /* Yellow */
        }
        tr.critical {
            background-color: #ffa533; /* Orange */
        }
        tr.head {
            background-color: #808B96; /* Gray */
        }
        tr.ok {
            background-color: #90EE90; /* Light Green */
        }
        tr.normal {
            background-color: white; /* White for normal ASM usage */
        }
    </style>
</head>
<body>
<h1 style="text-align: center;">Health check report for Non-Prod OEM 24ai $1</h1>
EOF
}

# Get database list
get_database_list() {
    sqlplus -s "$REPO_CONNECT" << EOF > $OUTPUT_DIR/db_list
SET PAGESIZE 0
col DATABASE_NAME for a30
set lines 200
col DATABASE_VERSION for a20
col SERVER for a30
col OS for a20
col OS_VERSION for a60
set feedback off

SELECT db.TARGET_NAME DATABASE_NAME,
       db.TYPE_QUALIFIER1 DATABASE_VERSION,
       os.TARGET_NAME SERVER,
       os.TYPE_QUALIFIER1 OS,
       os.TYPE_QUALIFIER2 OS_VERSION
FROM SYSMAN.MGMT\$TARGET db, SYSMAN.MGMT\$TARGET os
WHERE db.HOST_NAME = os.TARGET_NAME
  AND db.target_type in ('rac_database','oracle_database','oracle_pdb')
  AND os.target_type = 'host'
  AND os.TYPE_QUALIFIER1 = '$1'
ORDER BY 1;
EOF
    sed -i '/^$/d' $OUTPUT_DIR/db_list
}

# Initialize ASM report file (Linux only)
init_asmreport_file() {
    cat "$OUTPUT_DIR/HealthCheck_Report_head" > "$OUTPUT_DIR/${HeathCheck_Report_File}"
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
<h2 style="text-align: center;">ASM USAGE</h2>
<table>
    <tr class="head">
        <th>TARGET Server</th>
        <th>DISKGROUP</th>
        <th>TOTAL_GB</th>
        <th>FREE_GB</th>
        <th>USED%</th>
    </tr>
EOF
}

# Generate ASM report (Linux only)
generate_asm_report() {
    init_asmreport_file
    # Process each database
    awk '{print $1 " " $3}' $OUTPUT_DIR/db_list | while read db_name server_name; do

    sqlplus -s "$REPO_CONNECT" <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
        SET PAGESIZE 0
        col DATABASE_NAME for a30
        set lines 200
        col DATABASE_VERSION for a20
        col SERVER for a30
        col OS for a20
        col OS_VERSION for a60
        set head off
        set feedback off
        
        SELECT
            -- Check if the result meets the threshold, and use CASE to add class (critical, warning, normal)
            '<tr class="' ||
            CASE
                WHEN MAX(CASE WHEN mc.METRIC_COLUMN = 'percent_used' THEN ROUND(to_number(mc.VALUE)) END) >= 90 THEN 'critical' -- Red for critical
                WHEN MAX(CASE WHEN mc.METRIC_COLUMN = 'percent_used' THEN ROUND(to_number(mc.VALUE)) END) >= 80 THEN 'warning' -- Yellow for warning
                ELSE 'normal' -- Default for normal
            END || '">' ||
            '<td>' || mc.TARGET_NAME || '</td>' ||
            '<td>' || mc.KEY_VALUE || '</td>' ||
            '<td>' || -- Total GB
            ROUND(MAX(CASE WHEN mc.METRIC_COLUMN = 'total_mb' THEN (to_number(mc.VALUE))/1024 END), 2) || '</td>' ||
            '<td>' || -- Free GB
            ROUND(MAX(CASE WHEN mc.METRIC_COLUMN = 'free_mb' THEN (to_number(mc.VALUE))/1024 END), 2) || '</td>' ||
            '<td>' || -- Percent Used
            MAX(CASE WHEN mc.METRIC_COLUMN = 'percent_used' THEN ROUND(to_number(mc.VALUE), 2) END) || '%</td>' ||
            '</tr>' AS html_row
        FROM sysman.MGMT\$METRIC_CURRENT mc,
             sysman.MGMT\$TARGET mt
        WHERE mc.METRIC_NAME = 'DiskGroup_Usage'
          AND mc.METRIC_COLUMN IN ('percent_used', 'free_mb', 'total_mb')
          AND mc.TARGET_NAME = mt.TARGET_NAME
          AND mt.target_type = 'osm_instance'
          AND mt.HOST_NAME = '$server_name'
        GROUP BY mc.TARGET_NAME, mc.KEY_VALUE
        HAVING COUNT(*) > 0;
EOF

    done

    echo "</table>" >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
}

# Generate ASM "Not Applicable" message for AIX
generate_asm_not_applicable() {
    cat "$OUTPUT_DIR/HealthCheck_Report_head" > "$OUTPUT_DIR/${HeathCheck_Report_File}"
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
<h2 style="text-align: center;">ASM USAGE</h2>
<table>
    <tr class="head">
        <th>STATUS</th>
    </tr>
    <tr class="ok">
        <td style="text-align: center; padding: 20px; font-weight: bold;">Not Applicable for AIX Servers</td>
    </tr>
</table>
EOF
}

# Initialize tablespace report file
init_tbsreport_file() {
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
<h2 style="text-align: center;">Tablespace Report - Need Attention </h2>
<table>
    <tr class="head">
        <th>TARGET DB</th>
        <th>TARGET Server</th>
        <th>Tablespace (% Used)</th>
    </tr>
EOF
}

# Generate tablespace data for a specific database
generate_tablespace_data() {
    init_tbsreport_file
    # Process each database
    awk '{print $1 " " $3}' $OUTPUT_DIR/db_list | while read db_name server_name; do

    sqlplus -s "$REPO_CONNECT" <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"

SET PAGESIZE 0
COL DATABASE_NAME FOR A30
SET LINES 200
COL DATABASE_VERSION FOR A20
COL SERVER FOR A30
COL OS FOR A20
COL OS_VERSION FOR A60
SET HEAD OFF
SET FEEDBACK OFF
-- Tablespace Usage Report (HTML rows) — one line per target, 85% threshold highlighting
WITH tablespace_data AS (
    SELECT
        target_name,
        host_name,
        tablespace_name,
        ROUND(tablespace_used_size / 1024 / 1024, 2) AS used_mb,
        ROUND(tablespace_size / 1024 / 1024, 2) AS total_mb,
        ROUND((tablespace_size - tablespace_used_size) / 1024 / 1024, 2) AS free_mb,
        ROUND((tablespace_used_size / tablespace_size) * 100, 2) AS used_percent,
        status,
        contents,
        collection_timestamp
    FROM sysman.mgmt\$db_tablespaces
    WHERE tablespace_size > 0
      and target_name='$db_name'
),
target_summary AS (
    SELECT
        target_name,
        host_name,
        COUNT(CASE WHEN used_percent >= 85 THEN 1 END) AS critical_tablespaces,
        MAX(CASE WHEN used_percent >= 85 THEN used_percent END) AS max_critical_used_percent,
        LISTAGG(
            CASE WHEN used_percent >= 85 THEN tablespace_name || '(' || used_percent || '%)' END,
            ', '
        ) WITHIN GROUP (ORDER BY used_percent DESC) AS critical_tablespace_list
    FROM tablespace_data
    GROUP BY target_name, host_name
)
SELECT
    '<tr class="' ||
        CASE
            WHEN NVL(max_critical_used_percent, 0) >= 90 THEN 'critical'
            WHEN NVL(max_critical_used_percent, 0) >= 85 THEN 'warning'
            ELSE 'ok'
        END || '">' ||
    '<td>' || target_name || '</td>' ||
    '<td>' || host_name || '</td>' ||
    '<td>' ||
        CASE
            WHEN NVL(critical_tablespaces, 0) > 0
                THEN critical_tablespace_list
            ELSE 'No tablespace used 85% above'
        END ||
    '</td>' ||
    '</tr>' AS row_html
FROM target_summary;

EOF

   done

cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
</table>
EOF
}

# Initialize CPU report file
init_cpureport_file() {
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
<h2 style="text-align: center;">CPU Utilization </h2>
<table>
    <tr class="head">
        <th>TARGET Server</th>
        <th>CPU Utilization%</th>
    </tr>
EOF
}

# Generate CPU report
generate_cpu_report() {
    init_cpureport_file
    # Process each database
    awk '{print $1 " " $3}' $OUTPUT_DIR/db_list | while read db_name server_name; do

    sqlplus -s "$REPO_CONNECT" <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
        SET PAGESIZE 0
        col DATABASE_NAME for a30
        set lines 200
        col DATABASE_VERSION for a20
        col SERVER for a30
        col OS for a20
        col OS_VERSION for a60
        set head off
        set feedback off

        SELECT
            '<tr class="' ||
            CASE
                WHEN round(to_number(VALUE)) >= 90 THEN 'critical' -- Red for critical
                WHEN round(to_number(VALUE)) >= 80 THEN 'warning' -- Yellow for warning
                ELSE 'low' -- Green for normal
            END || '">' ||
            '<td>' || '$server_name' || '</td>' ||
            '<td>' || ROUND(to_number(VALUE), 2) || '%</td>' ||
            '</tr>' AS html_row
        FROM sysman.MGMT\$METRIC_CURRENT
        WHERE metric_name = 'Load'
          AND metric_column = 'cpuUtil'
          AND target_name = '$server_name'
        GROUP BY VALUE;
EOF

    done

    echo "</table>" >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
}

# Initialize DB Growth report file
init_dbgreport_file() {
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
<h2 style="text-align: center;">Database Growth - Last 7 Months (Including Current Month)</h2>
<p style="margin: 10px auto; max-width: 80%; font-size: 12px; color: #666; text-align: left;">
<strong>Note:</strong> Consistent 0% allocated growth in databases suggests good capacity planning (pre-allocated). 
Variable used space growth is normal due to data purging, batch processing cycles, and transaction volume fluctuations.
</p>
<table>
    <tr class="head">
        <th>TARGET DB</th>
        <th>TARGET Server</th>
        <th>MONTH_DT</th>
        <th>ALLOCATED_GB</th>
        <th>USED_GB</th>
        <th>ALLOCATED_GROWTH%</th>
        <th>USED_GROWTH%</th>
    </tr>
EOF
}

# Generate DB Growth report with complete month coverage
generate_dbgrowth_report() {
    init_dbgreport_file
    # Process each database
    awk '{print $1 " " $3}' $OUTPUT_DIR/db_list | while read db_name server_name; do

    sqlplus -s "$REPO_CONNECT" <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
        SET PAGESIZE 0
        col DATABASE_NAME for a30
        set lines 200
        col DATABASE_VERSION for a20
        col SERVER for a30
        col OS for a20
        col OS_VERSION for a60
        set head off
        set feedback off
        
        -- Simple approach: Get data for last 7 months without complex CTEs
        WITH dbsz_monthly AS (
            SELECT
                target_name,
                trunc(rollup_timestamp, 'MONTH') month_dt,
                metric_column,
                ROUND(AVG(maximum), 2) as avg_value
            FROM SYSMAN.MGMT\$metric_daily
            WHERE target_type IN ('rac_database', 'oracle_database', 'oracle_pdb')
              AND metric_name = 'DATABASE_SIZE'
              AND metric_column IN ('ALLOCATED_GB', 'USED_GB')
              AND target_name = '$db_name'
              AND rollup_timestamp >= ADD_MONTHS(TRUNC(SYSDATE, 'MONTH'), -6)
              AND maximum IS NOT NULL
              AND maximum > 0
            GROUP BY target_name, trunc(rollup_timestamp, 'MONTH'), metric_column
        ),
        dbsz_pivot AS (
            SELECT
                target_name,
                month_dt,
                SUM(CASE WHEN metric_column = 'USED_GB' THEN avg_value END) as used_gb,
                SUM(CASE WHEN metric_column = 'ALLOCATED_GB' THEN avg_value END) as allocated_gb
            FROM dbsz_monthly
            GROUP BY target_name, month_dt
        ),
        dbsz_with_growth AS (
            SELECT
                target_name,
                month_dt,
                allocated_gb,
                used_gb,
                LAG(allocated_gb) OVER (ORDER BY month_dt) AS prev_allocated_gb,
                LAG(used_gb) OVER (ORDER BY month_dt) AS prev_used_gb
            FROM dbsz_pivot
        )
        SELECT
            '<tr><td>' || target_name || '</td>' ||
            '<td>' || '$server_name' || '</td>' ||
            '<td>' || TO_CHAR(month_dt, 'MON-YYYY') || '</td>' ||
            '<td>' || NVL(ROUND(allocated_gb, 2), 0) || '</td>' ||
            '<td>' || NVL(ROUND(used_gb, 2), 0) || '</td>' ||
            '<td>' || 
            CASE
                WHEN prev_allocated_gb IS NOT NULL AND prev_allocated_gb > 0 
                     AND ABS(allocated_gb - prev_allocated_gb) > 0.01 THEN
                    ROUND(((allocated_gb - prev_allocated_gb) / prev_allocated_gb) * 100, 2)
                ELSE 0
            END || '%</td>' ||
            '<td>' || 
            CASE
                WHEN prev_used_gb IS NOT NULL AND prev_used_gb > 0 
                     AND ABS(used_gb - prev_used_gb) > 0.01 THEN
                    ROUND(((used_gb - prev_used_gb) / prev_used_gb) * 100, 2)
                ELSE 0
            END || '%</td></tr>' AS html_row
        FROM dbsz_with_growth
        ORDER BY month_dt;

EOF

done

echo "</table>" >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
}

# Close HTML report
finish_report() {
    cat <<EOF >> "$OUTPUT_DIR/${HeathCheck_Report_File}"
</body>
</html>
EOF
}

# Main function
main() {
    for os in AIX Linux ; do
        init_config $os
        create_html_header $os
        get_database_list $os
        
        # Generate ASM report (ASM Candidate Disk section removed as requested)
        if [ "$os" = "Linux" ]; then
            generate_asm_report
        else
            # For AIX, show "Not Applicable" message
            generate_asm_not_applicable
        fi
        
        generate_tablespace_data
        generate_cpu_report
        generate_dbgrowth_report
        finish_report

        (
        echo "To: oracledbateam@example.com"

        echo "Subject: Health check report for Non-Prod OEM 24ai $os"
        echo "Content-Type: text/html"
        cat  "$OUTPUT_DIR/${HeathCheck_Report_File}"
        ) | sendmail -t

    done
}

# Execute main function
main

