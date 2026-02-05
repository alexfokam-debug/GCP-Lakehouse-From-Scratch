# ADR-001 — Why an Analytics Lakehouse on Google Cloud

## Status

Accepted

## Context

The organization needs to analyze large volumes of structured and semi-structured data
while ensuring scalability, cost efficiency, and governance.
Traditional data warehouses lack flexibility for raw data storage, while pure data lakes
lack strong governance and SQL analytics capabilities.

The goal is to design a modern analytics platform that:

* Separates storage and compute
* Uses open data formats
* Supports multiple processing engines
* Enforces centralized governance

## Decision

We adopt an **Analytics Lakehouse architecture on Google Cloud**, combining:

* **Cloud Storage** as the system of record
* **Dataplex** for governance, cataloging, and data organization
* **BigLake** to provide unified access to data stored in Cloud Storage
* **BigQuery** as the primary analytics engine
* **Terraform** to provision and manage infrastructure as code

## Alternatives Considered

* **Traditional Data Warehouse only (BigQuery-managed tables)**
  Rejected due to limited flexibility for raw and semi-structured data and higher storage coupling.

* **Pure Data Lake (Cloud Storage + Spark only)**
  Rejected due to weaker SQL analytics, BI integration, and governance complexity.

* **Databricks-based Lakehouse**
  Not selected in order to stay fully aligned with native Google Cloud services and
  minimize operational overhead.

## Consequences

* Unified analytics across lake and warehouse data
* Open formats (Parquet / Iceberg) reduce vendor lock-in
* Centralized governance via Dataplex improves data discoverability and security
* Infrastructure is reproducible, auditable, and scalable through Terraform

## References

* Google Cloud Analytics Lakehouse architecture
* Google Cloud Professional Data Engineer certification objectives

