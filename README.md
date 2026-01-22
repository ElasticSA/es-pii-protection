# PII Protection Patterns for Elasticsearch

**NB: This is not an official component from Elastic, but rather a project of its employee(s)**

This project documents multiple approaches to achieving **Personally Identifiable Information (PII) protection** in Elasticsearch when it is used as a **unified data platform** by many users with different roles and access requirements.
The approaches described here are applicable to environments subject to **data‑protection and privacy regulations**, such as:

- GDPR (EU)
- UK GDPR
- CCPA / CPRA
- internal data‑handling and least‑privilege policies

The focus is on **practical, production‑ready patterns** that allow organizations to:

- ingest and retain sensitive data where required
- protect access to PII by default
- continue to use ECS‑based features (dashboards, detections, alerts)
- avoid data duplication or index explosion
- centralize enforcement inside Elasticsearch

---

## Core Problem
In many Elasticsearch deployments:

- Logs, metrics, and traces are shared across **many teams**
- Some users require access to **raw PII** (e.g. security, fraud, compliance)
- Most users do **not** require access to PII
- ECS‑based tooling (Elastic Security, Observability, dashboards) expects
  standard ECS fields to exist
  
Naïve approaches such as:

- removing PII at ingest time
- indexing separate “redacted” and “full” datasets
- duplicating indices per audience

either **break ECS features**, **increase operational complexity**, or **prevent legitimate use cases**.
This repository explores alternative designs that keep **one dataset**, but provide **different views** depending on user permissions.

---

## Approaches Documented


### ✅ Runtime Fields (RTF) + Role‑Based Access Control (RBAC)

This approach combines:

- **Ingest pipelines** to isolate PII at write time
- **Runtime fields** to present ECS‑compatible views at read time
- **Field‑level security (RBAC)** to control access to sensitive fields
This allows:
- the same index to serve multiple audiences
- PII to be stored securely
- ECS‑dependent features to continue working unchanged

See [`rtf+rbac/`](./rtf+rbac) for details.

---
