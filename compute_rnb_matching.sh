#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/.env"

export PGPASSWORD=$DB_PASSWORD


BATCH=50000

# Récupérer les bornes
MIN_ID=$(psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT min(id) FROM extracted_buildings;" | tr -d ' ')
MAX_ID=$(psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT max(id) FROM extracted_buildings;" | tr -d ' ')

psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view osm_relation_links;"
psql -qt -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "REFRESH MATERIALIZED  view outline_way_ids;"


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
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
    WITH
    filtered_osm AS (
      SELECT id AS osm_id, way, ST_Area(way) as osm_area
      FROM extracted_buildings
      WHERE id BETWEEN $START AND $END
        AND match_rnb_ids is null
        AND (wall IS NULL OR wall <> 'no')
        AND (shelter_type IS NULL OR shelter_type <> 'public_transport')
        AND (building IS NULL OR building NOT IN (
          'ruins','construction','static_caravan','ger','collapsed',
          'tent','tomb','abandoned','mobile_home','proposed',
          'destroyed','roof','no'
        ))
        AND st_isvalid(way)
    ),
    paired AS (
      SELECT
        f.osm_id, r.rnb_id,
        ST_Area(ST_Intersection(f.way, r.shape)) AS intersect_area,
        f.osm_area, ST_Area(r.shape) as rnb_area
      FROM filtered_osm AS f
      JOIN rnb_buildings AS r
        ON r.shape && f.way
        AND ST_Intersects(f.way, r.shape)
      WHERE  st_isvalid(r.shape)
    ),
    rec70 AS (
      SELECT
        osm_id, rnb_id,
        (intersect_area / LEAST(osm_area, rnb_area) * 100.0) AS pct_recouvrement
      FROM paired
      WHERE intersect_area > 0
        AND (intersect_area / LEAST(osm_area, rnb_area) * 100.0) > 70.0
    ),
    rnb_counts AS (
      SELECT
        rnb_id,
        COUNT(*) AS occurrences
      FROM rec70
      GROUP BY rnb_id
    ),

    -- 5) Joindre pour pouvoir distinguer 'splited'
    rec_joined AS (
      SELECT
        r.osm_id,
        r.rnb_id,
        r.pct_recouvrement,
        c.occurrences
      FROM rec70 AS r
      JOIN rnb_counts AS c USING (rnb_id)
    ),
    agg AS (
      SELECT
        osm_id,
        string_agg(rnb_id::text, ';')             AS match_rnb_ids,
        round(avg(pct_recouvrement)) / 100.0      AS match_rnb_score,
        CASE
          WHEN COUNT(*) > 1 THEN 'multiple'
          WHEN MAX(occurrences) > 1 THEN 'splited'
          ELSE NULL
        END   AS match_rnb_diff
      FROM rec_joined
      GROUP BY osm_id
    )
  UPDATE extracted_buildings AS eb
  SET
    match_rnb_ids   = a.match_rnb_ids,
    match_rnb_score = a.match_rnb_score,
    match_rnb_diff  = a.match_rnb_diff
  FROM agg AS a
  WHERE eb.id = a.osm_id;
  "
  
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