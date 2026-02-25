## 🏗️ Infrastructure as Code & Storage Foundation

### Why Infrastructure as Code (Terraform)

This project uses **Terraform** to provision Google Cloud resources following an **Infrastructure as Code (IaC)** approach.

This choice ensures:

* **Reproducibility**: the same infrastructure can be recreated consistently across environments
* **Versioning**: infrastructure changes are tracked through Git
* **Auditability**: every change is explicit and reviewable
* **Scalability**: the architecture can evolve without manual configuration drift

Terraform modules are used to promote **reusability** and **clear separation of concerns**.

---

### Why Cloud Storage as RAW layer

The **RAW layer** is implemented using **Google Cloud Storage (GCS)** and represents the first landing zone of the lakehouse.

This layer is designed to:

* Store **immutable, raw data** as received from source systems
* Preserve **original formats** (CSV, JSON, Parquet, Avro, etc.)
* Enable **reprocessing** and backfills when transformation logic evolves
* Serve as the foundation for governance and lineage

---

### Naming convention

Buckets follow a clear and explicit naming standard:

```
<project-id>-<layer>-<environment>
```

Example:

```
lakehouse-486419-raw-dev
```

This convention improves:

* Resource discoverability
* Environment isolation
* Operational clarity across teams

---

### Labels, Governance & FinOps

All storage resources are created with **mandatory labels**, combining:

* **Platform-enforced labels** (environment, data layer)
* **Project-specific labels** (owner, cost center, platform)

Labels enable:

* **Governance**: clear identification of data layers (raw vs curated)
* **FinOps**: cost attribution and reporting
* **Operational visibility** across the GCP organization

---

### Security & resilience

The RAW bucket is configured with:

* **Uniform bucket-level access** (IAM-based security)
* **Object versioning enabled**, allowing:

  * accidental deletion recovery
  * audit and rollback capabilities

These settings align with Google Cloud best practices for enterprise data platforms.


















