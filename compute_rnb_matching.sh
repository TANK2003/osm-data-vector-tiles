#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/.env"

export PGPASSWORD=$DB_PASSWORD

# horodatage insert buildings if skipped from triggers
insert_buildings_start=$(date +%s.%N)
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "./sql/insert_buildings_not_in_extracted_buildings.sql"
insert_buildings_end=$(date +%s.%N)
insert_buildings_duration=$(awk "BEGIN{print $insert_buildings_end - $insert_buildings_start}")
echo "  Insert buildings finish in ${insert_buildings_duration}s"

BATCH=50000

# Récupérer les bornes
MIN_ID=$(psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT min(id) FROM extracted_buildings;" | tr -d ' ')
MAX_ID=$(psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT max(id) FROM extracted_buildings;" | tr -d ' ')

psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view osm_relation_links;"
psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view outline_way_ids;"

psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view osm_buildings_relation_links;"
psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view osm_buildings_outer_ways;"


psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "./sql/update_parent_and_children.sql"

echo "Traitement de la table extracted_buildings, IDs de $MIN_ID à $MAX_ID par pas de $BATCH."

# horodatage total
script_start=$(date +%s.%N)

for (( START=MIN_ID; START<=MAX_ID; START+=BATCH )); do
  END=$(( START + BATCH - 1 ))
  echo
  echo "→ Batch IDs $START à $END"
  
  # horodatage batch
  batch_start=$(date +%s.%N)
  
  # exécution psql
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "./sql/compute_rnb_osm_matching.sql"
  
  # mesurer fin de batch
  batch_end=$(date +%s.%N)
  batch_duration=$(awk "BEGIN{print $batch_end - $batch_start}")
  echo "  Batch terminé en ${batch_duration}s"
done

# temps total
script_end=$(date +%s.%N)
total_duration=$(awk "BEGIN{print $script_end - $script_start}")
echo
echo "✅ Traitement complet en ${total_duration}s"