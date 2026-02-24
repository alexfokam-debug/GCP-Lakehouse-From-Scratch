variable "project_id" {
  description = "Project ID (ex: lakehouse-dev-486419)"
  type        = string
}

variable "labels" {
  description = "Map de labels à appliquer au projet."
  type        = map(string)
}