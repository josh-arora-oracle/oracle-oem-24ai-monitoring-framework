# Oracle OEM 24ai Monitoring Framework

## Overview

This repository contains a reusable Oracle Enterprise Manager (OEM) 24ai automation framework for:

- CPU spike forensic classification
- Automated health check reporting
- Tablespace usage monitoring
- HTML executive report generation
- Secure wallet-based repository connectivity

All files are sanitized for public release. No client data is included.

---

## Components

### 1. CPU Forensics Script
Generates structured HTML reports analyzing CPU usage spikes over a defined lookback window.  
Designed for non-production scope but adaptable for production.

### 2. OEM Health Check Script
Generates HTML-based health summaries including:
- Database utilization
- Tablespace thresholds
- Target monitoring status
- Capacity indicators

### 3. Sample HTML Outputs
Included sanitized sample reports demonstrate:
- Structured formatting
- Capacity trend analysis
- Operational review formatting

---

## Architecture Approach

- Repository queries executed via SQL*Plus
- Secure alias-based connection:
  /@OEM_REPO_ALIAS as sysdba
- No embedded credentials
- Designed for enterprise monitoring workflows

---

## Security & Compliance

- All hostnames replaced with dummy values
- All database names replaced with placeholders
- All tablespace names anonymized
- All email references replaced
- No client-identifiable metadata retained

---

## Educational Value

This framework demonstrates:

- Observability-driven RCA methodology
- OEM repository reporting techniques
- CPU spike classification logic
- Secure automation patterns
- HTML-based executive reporting

---

## Intended Audience

- Oracle DBAs
- Enterprise Monitoring Teams
- OEM Administrators
- Infrastructure Engineers

---

## License

MIT
