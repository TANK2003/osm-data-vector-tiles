WITH
    filtered_osm AS (
      SELECT id AS osm_id, way, ST_Area(way) as osm_area
      FROM extracted_buildings
      WHERE id BETWEEN :START AND :END
        AND rnb is not null
        AND match_rnb_ids is null
        AND (wall IS NULL OR wall <> 'no')
        AND (shelter_type IS NULL OR shelter_type <> 'public_transport')
        AND ( building NOT IN (
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