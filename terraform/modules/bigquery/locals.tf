locals {
  raw_external_tables_effective = (
    var.enable_sales_orders_external_tables
    ? var.raw_external_tables
    : {
      for k, v in var.raw_external_tables : k => v
      if !(k == "orders" || k == "sales_transactions")
    }
  )

  raw_table_cfg = {
    for k, v in local.raw_external_tables_effective : k => {
      source_format            = v.source_format
      source_uris              = v.source_uris
      autodetect               = try(v.autodetect, true)
      hive_source_prefix       = try(v.hive_source_prefix, null)
      require_partition_filter = try(v.require_partition_filter, false)
    }
  }
}