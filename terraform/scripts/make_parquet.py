"""
Génère un petit dataset de démo et l'exporte en Parquet.
Objectif : avoir un fichier réel à déposer dans le bucket RAW.
"""

import pandas as pd

# Données d'exemple (typées et réalistes)
df = pd.DataFrame(
    [
        {"order_id": 1, "customer_id": 101, "amount": 49.90, "order_date": "2026-02-01"},
        {"order_id": 2, "customer_id": 102, "amount": 15.00, "order_date": "2026-02-02"},
        {"order_id": 3, "customer_id": 101, "amount": 120.00, "order_date": "2026-02-03"},
    ]
)

# Convertir la date en type date (mieux pour BigQuery)
df["order_date"] = pd.to_datetime(df["order_date"]).dt.date

# Export Parquet
output_path = "/tmp/orders.parquet"
df.to_parquet(output_path, index=False)

print(f"✅ Parquet généré : {output_path}")
print(df.dtypes)
print(df)
