# SKENC – Shared‑Key Encryption for Elasticsearch

**NB: This is still in development and is not full tested**

**SKENC** documents a pattern for protecting **Personally Identifiable Information (PII)**
in Elasticsearch by applying **shared‑key encryption before indexing**.
Unlike access‑control‑based approaches, SKENC ensures that Elasticsearch
**never stores or processes plaintext PII**.

---

## Problem Addressed
In some environments:

- Elasticsearch cannot be fully trusted with sensitive data
- PII access must be cryptographically controlled
- Access via Kibana or APIs must never expose raw values
- Regulatory or contractual requirements mandate encryption before indexing

In these cases, access control alone is insufficient.
SKENC addresses this by enforcing PII protection **outside Elasticsearch**.

---

## Design Overview

### Ingest‑time encryption

PII fields are encrypted during ingestion, typically in Logstash:

Elastic Agent
↓
Logstash (PII encryption)
↓
Elasticsearch (encrypted PII only)

Elasticsearch stores only encrypted values.
No decryption keys are present in the cluster.

---

## Encryption Model

### Scalar fields

Scalar PII fields (for example):

- user.email
- user.name
- host.name
- user.id

are encrypted using **AES‑256‑CBC** with a shared secret key.

Encrypted values are stored inline in a structured format:


\<field_name\>:\<salt\>:\<base64(iv + ciphertext)\>

This format allows:

- deterministic parsing
- offline decryption
- key rotation via re‑encryption

---

### IP addresses

IP addresses are handled separately to preserve analytical usefulness.

- IPv4: upper /16 preserved, lower /16 encrypted
- IPv6: upper /64 preserved, lower /64 encrypted

The result is:

- a valid IP address
- reversible with the shared key
- suitable for subnet‑level aggregation and dashboards

---

## Decryption

Decryption is performed using a standalone Bash utility:

- `esdec.sh`

The tool:

- fetches documents directly from Elasticsearch
- outputs human‑readable YAML
- decrypts AES‑encrypted fields
- reverses IPv4 and IPv6 transformations

No decryption occurs inside Elasticsearch or Kibana.

---

## Configuration

SKENC tooling uses a curl‑style configuration file that includes:

- Elasticsearch connection details
- Authentication headers
- The shared PII key (or a path to it)

Conceptual example:

```
#es_url "https://localhost:9200"
#pii_key "/secure/path/pii.key"
header "Authorization: ApiKey BASE64_KEY"
# Need always for REST API
header "Accept: application/json"
header "Content-Type: application/json"
```

---

## Security Model

- Elasticsearch never sees plaintext PII
- Access to encrypted data does not imply access to PII
- Possession of the shared key is required for decryption
- Key management and rotation are external concerns

This model aligns with **zero‑trust assumptions** for the data platform.

---

## Relationship to RTF + RBAC

SKENC and RTF+RBAC solve **different problems**:

- RTF+RBAC focuses on **controlled access within Elasticsearch**
- SKENC focuses on **cryptographic isolation from Elasticsearch**

They are not mutually exclusive and may be used in different tiers
or environments depending on risk and compliance requirements.

---

## Status

This approach is a working reference implementation.
It is expected to evolve as additional edge cases and operational
requirements are explored.
