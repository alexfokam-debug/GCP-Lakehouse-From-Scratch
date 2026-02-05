# GCP Lakehouse From Scratch

End-to-end **Analytics Lakehouse** on **Google Cloud**, built **from scratch** and automated with **Terraform + CI/CD**.

This project demonstrates how to unify a data lake and a data warehouse by combining:

* **Cloud Storage** (open formats: Parquet / Iceberg)
* **Dataplex** (governance, catalog, data quality hooks)
* **BigLake + BigQuery** (unified access + analytics)
* *(optional)* **Dataproc** for Spark-based batch processing
* *(optional)* **Looker Studio / Tableau** for BI consumption

> Goal: showcase a clean, enterprise-like implementation you can deploy on your own GCP project.

---

## Architecture

![Architecture](docs/architecture/lakehouse.png)

**High-level flow**

1. Data lands in **GCS (RAW)**
2. **Dataplex** organizes assets into a lake and zones
3. Tables are exposed as **BigLake** and queried in **BigQuery**
4. Transformations run via **BigQuery SQL** and/or **Dataproc (Spark)**
5. Curated datasets are consumed by **BI** and **ML** (optional)

---

## Repository structure

```
.
├── docs/
│   └── architecture/
├── terraform/
│   ├── envs/
│   │   ├── dev/
│   │   └── prod/
│   ├── modules/
│   └── main.tf
├── sql/
├── .github/workflows/
└── README.md
```

---

## Prerequisites

* A **GCP project** with billing enabled
* Local tooling:

  * `gcloud`
  * `terraform`
  * `git`

---

## Quickstart (dev)

> Coming next: full Terraform bootstrap + remote state + CI/CD pipeline.

---

## Roadmap

* [ ] Bootstrap Terraform (providers, backend state, variables)
* [ ] Provision GCS buckets (raw/curated)
* [ ] Create Dataplex lake + zones + assets
* [ ] Create BigQuery dataset + BigLake connection + external tables
* [ ] Add curated layer (BQ tables/views)
* [ ] CI/CD (terraform fmt/validate/plan/apply)
* [ ] Optional: Dataproc Spark job writing Iceberg

---

## Disclaimer

This repository is for learning/portfolio purposes and is inspired by Google Cloud Lakehouse reference patterns. It is **not** a production landing zone by itself.
