#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# BigQuery runner (bq CLI) - Enterprise style
#
# - Exécute les scripts SQL par couche:
#     sql/01_external/*.sql(.tpl)
#     sql/02_curated/*.sql(.tpl)
#     sql/03_gold/*.sql(.tpl)
# - Rend les templates *.sql.tpl via envsubst -> *.sql
# - Supporte:
#     --from-layer 02_curated
#     --to-layer   03_gold
#     --dry-run
#     --quiet
# ============================================================

# ---------- Helpers ----------
usage() {
  cat <<EOF
Usage:
  PROJECT_ID=... ENV=dev LOCATION=EU ./terraform/scripts/run_bigquery.sh [options]

Options:
  --from-layer <01_external|02_curated|03_gold>   (default: 01_external)
  --to-layer   <01_external|02_curated|03_gold>   (default: 03_gold)
  --dry-run                                      (n'exécute pas, affiche)
  --quiet                                        (réduit les logs)
  -h|--help
EOF
}

log() {
  # log standard
  echo "$@"
}

qlog() {
  # log uniquement si non quiet
  if [[ "${QUIET}" != "1" ]]; then
    echo "$@"
  fi
}

die() {
  echo " $*" >&2
  exit 1
}

# ---------- Args ----------
FROM_LAYER="01_external"
TO_LAYER="03_gold"
DRY_RUN="0"
QUIET="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-layer)
      FROM_LAYER="${2:-}"; shift 2 ;;
    --to-layer)
      TO_LAYER="${2:-}"; shift 2 ;;
    --dry-run)
      DRY_RUN="1"; shift 1 ;;
    --quiet)
      QUIET="1"; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Option inconnue: $1 (utilise --help)" ;;
  esac
done

# ---------- Required env vars ----------
: "${PROJECT_ID:?Variable PROJECT_ID manquante (ex: PROJECT_ID=lakehouse-486419)}"
: "${ENV:?Variable ENV manquante (ex: ENV=dev)}"
: "${LOCATION:?Variable LOCATION manquante (ex: LOCATION=EU)}"

# ---------- Derived / defaults ----------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SQL_ROOT="${PROJECT_ROOT}/sql"

# Buckets/datasets/connection naming (aligné à ton projet Terraform)
RAW_BUCKET="${PROJECT_ID}-raw-${ENV}"
CURATED_DATASET="curated_${ENV}"
BIGLAKE_CONNECTION="biglake_conn_${ENV}"

# IMPORTANT: rendre visibles les variables à envsubst (sinon placeholders restent)
export PROJECT_ID ENV LOCATION PROJECT_ROOT SQL_ROOT RAW_BUCKET CURATED_DATASET BIGLAKE_CONNECTION

# ---------- Banner ----------
if [[ "${QUIET}" != "1" ]]; then
  cat <<EOF
============================================
BigQuery runner (bq CLI)
PROJECT_ID        = ${PROJECT_ID}
LOCATION          = ${LOCATION}
ENV               = ${ENV}
RAW_BUCKET        = ${RAW_BUCKET}
CURATED_DATASET   = ${CURATED_DATASET}
BIGLAKE_CONNECTION= ${BIGLAKE_CONNECTION}
PROJECT_ROOT      = ${PROJECT_ROOT}
SQL_ROOT          = ${SQL_ROOT}
============================================
EOF
fi

# ---------- Layers order ----------
layers=("01_external" "02_curated" "03_gold")

# Validate layer names
valid_layer() {
  local x="$1"
  for l in "${layers[@]}"; do
    [[ "$l" == "$x" ]] && return 0
  done
  return 1
}
valid_layer "${FROM_LAYER}" || die "from-layer invalide: ${FROM_LAYER}"
valid_layer "${TO_LAYER}" || die "to-layer invalide: ${TO_LAYER}"

# Decide range
in_range="0"

# ---------- Execute ----------
for layer in "${layers[@]}"; do
  [[ "${layer}" == "${FROM_LAYER}" ]] && in_range="1"
  [[ "${in_range}" == "1" ]] || continue

  layer_dir="${SQL_ROOT}/${layer}"
  qlog ""
  qlog "▶️  Layer: ${layer}"
  qlog "   Dossier: ${layer_dir}"

  if [[ ! -d "${layer_dir}" ]]; then
    qlog "⚠️  Dossier absent, ignoré: ${layer_dir}"
  else
    # List .sql and .sql.tpl (compatible macOS bash 3.2 : pas de mapfile)
    files=()
    for f in "${layer_dir}"/*.sql "${layer_dir}"/*.sql.tpl; do
      [[ -e "$f" ]] && files+=("$f")
    done

    # Tri stable
    IFS=$'\n' files_sorted=($(printf "%s\n" "${files[@]}" | sort))
    unset IFS

    if [[ ${#files_sorted[@]} -eq 0 ]]; then
      qlog "   (aucun script trouvé)"
    else
      for f in "${files_sorted[@]}"; do
        # Render template if needed
        if [[ "$f" == *.sql.tpl ]]; then
          rendered="${f%.tpl}"  # retire .tpl => *.sql
          qlog "   (template) $(basename "$f") -> $(basename "$rendered")"
          envsubst < "$f" > "$rendered"
          sql_to_run="$rendered"
        else
          sql_to_run="$f"
        fi

        qlog "   → Exécution: $(basename "$sql_to_run")"

        if [[ "${DRY_RUN}" == "1" ]]; then
          log "DRY_RUN: bq query --use_legacy_sql=false --location=${LOCATION} < ${sql_to_run}"
        else
          # --quiet option bq: réduit output, mais on garde DONE/erreurs.
          if [[ "${QUIET}" == "1" ]]; then
            bq --quiet query --use_legacy_sql=false --location="${LOCATION}" < "${sql_to_run}"
          else
            bq query --use_legacy_sql=false --location="${LOCATION}" < "${sql_to_run}"
          fi
        fi
      done
    fi
  fi

  [[ "${layer}" == "${TO_LAYER}" ]] && break
done

qlog ""
qlog "🎉 Terminé. Tous les scripts SQL ont été exécutés (si présents)."