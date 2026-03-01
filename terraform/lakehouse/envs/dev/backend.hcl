bucket = "lakehouse-terraform-states-486419"
prefix = "lakehouse/dev"terraform -chdir=terraform/lakehouse state push /tmp/lakehouse.tfstate
