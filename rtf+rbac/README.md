# PII Protection Using Runtime Fields and RBAC

**NB: This is still in development and is not full tested**

This document describes a **PII-protection pattern** for Elasticsearch based on:

- Ingest pipelines (write‑time transformation)
- Runtime fields (read‑time projection)
- Role‑based field‑security (RBAC)

The goal is to protect access to PII **without breaking ECS‑based features**
such as dashboards, visualizations, alerts, and detection rules.

---

## Design Goals

This approach is designed to:

- Maintain a **single source of truth** (one index / data stream)
- Preserve **ECS field names** for compatibility
- Allow **different users to see different values** for the same ECS field
- Avoid index duplication or re‑ingestion
- Centralize enforcement inside Elasticsearch

---

## High‑Level Architecture

### At ingest time

Incoming documents contain ECS fields with potential PII, for example:

- user.email
- source.ip
- host.name

A dedicated **PII protection ingest pipeline**:

- moves original values to `real.*`
- writes pseudonymised values to `pseudo.*`
- removes the original ECS fields

Example transformation;

user.email = alice@example.com

becomes;

real.user.email = alice@example.com
pseudo.user.email = email-X7kD8k...

---

### How the pipeline is applied

The PII protection logic lives in a **single reusable ingest pipeline**
named `pii-protection`.

Both logs and metrics data streams invoke this pipeline via lightweight
custom pipelines.

The pipeline includes a configurable org_ips parameter that controls
which IP addresses are anonymised.
It is currently prepopulated with common private IPv4 and IPv6 address
ranges.

#### `logs@custom` and `metrics@custom`

These pipelines contain the same content:

- A single processor
- That invokes the `pii-protection` pipeline
- No additional logic

Their purpose is to **hook PII protection into Fleet / integration pipelines**
without duplicating logic.


This keeps:

- PII handling centralized
- integration pipelines clean
- future changes easy to apply in one place

---

## Query-time Field Projection (Runtime Fields)

At query time, **runtime fields** recreate ECS fields such as `user.email
by reading from either `real.*` or `pseudo.*`.

The resolution logic is:

1. If the user is allowed to see `real.*`, runtime fields resolve to real data
2. Otherwise, runtime fields fall back to pseudonymised values

From the user’s perspective, ECS fields still exist.

For a non‑privileged user:

user.email = email-X7kD8k...

For a privileged user:

user.email = alice@example.com

No dashboards, visualizations, or queries need to change.

---

## Role‑Based Access Control

### Preventing access to real PII

Most users should not see raw PII,.

Q role like the following prevents access to all `real.*` fields while still
allowing ECS fields to function via runtime fields:

- Index privileges: read on logs-* and metrics-*
- Field‑level security: grant all fields except `real.*`
- Kibana read access

Users with this role:

- cannot access real.*
- see pseudonymised values via runtime ECS fields
- can still use dashboards, alerts, and ECS-‑dependent features

---

### Allowing access to real PII

Users with additional privileges (for example security, fraud, or compliance
teams) can be granted access to `real.*`.

For those users:

- runtime fields resolve to real values
- ECS fields transparently show original data
- no dashboards, or queries need to change

---

### Why Runtime Fields?

Runtime fields are used because they:

- allow **late binding** of values
- respect **field‑llevel security**
