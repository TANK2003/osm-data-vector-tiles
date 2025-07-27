CREATE INDEX IF NOT EXISTS idx_tags_hstore_gin ON public.planet_osm_polygon USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_line_tags_hstore_gin ON public.planet_osm_line USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_planet_osm_rels_members_gin ON planet_osm_rels USING GIN (members);

\i outline_way.sql

CREATE TABLE IF NOT EXISTS  extracted_buildings (
    id SERIAL PRIMARY KEY,
    osm_id INTEGER,
    osm_type TEXT,
    type TEXT,
    is_part BOOLEAN,
    building TEXT,
    wall TEXT,
    building_type TEXT,
    name TEXT,
    height FLOAT,
    min_height FLOAT,
    levels INTEGER,
    min_level INTEGER,
    material TEXT,
    roof_height FLOAT,
    roof_levels INTEGER,
    roof_material TEXT,
    roof_type TEXT,
    roof_orientation TEXT,
    roof_direction FLOAT,
    roof_color TEXT,
    color TEXT,
    windows TEXT,
    default_roof BOOLEAN,
    rnb TEXT,
    diff_rnb TEXT,
    shelter_type TEXT,
    parent_and_children jsonb,
    way geometry(Geometry, 4326)
);

ALTER TABLE extracted_buildings
  ADD COLUMN ombb00  double precision
    GENERATED ALWAYS AS (
      ST_X(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 1
        )
      )
    ) STORED,
  ADD COLUMN ombb01  double precision
    GENERATED ALWAYS AS (
      ST_Y(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 1
        )
      )
    ) STORED,
  ADD COLUMN ombb10  double precision
    GENERATED ALWAYS AS (
      ST_X(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 2
        )
      )
    ) STORED,
  ADD COLUMN ombb11  double precision
    GENERATED ALWAYS AS (
      ST_Y(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 2
        )
      )
    ) STORED,
  ADD COLUMN ombb20  double precision
    GENERATED ALWAYS AS (
      ST_X(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 3
        )
      )
    ) STORED,
  ADD COLUMN ombb21  double precision
    GENERATED ALWAYS AS (
      ST_Y(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 3
        )
      )
    ) STORED,
  ADD COLUMN ombb30  double precision
    GENERATED ALWAYS AS (
      ST_X(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 4
        )
      )
    ) STORED,
  ADD COLUMN ombb31  double precision
    GENERATED ALWAYS AS (
      ST_Y(
        ST_PointN(
          ST_ExteriorRing(
            ST_OrientedEnvelope(
              ST_Transform(way,3857)
            )
          ), 4
        )
      )
    ) STORED;


ALTER TABLE extracted_buildings
ADD COLUMN match_rnb_ids TEXT,
ADD COLUMN match_rnb_score FLOAT,
ADD COLUMN match_rnb_diff TEXT;


CREATE INDEX IF NOT EXISTS idx_extracted_buildings_way ON extracted_buildings USING GIST (way);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_osm_id ON extracted_buildings (osm_id);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_osm_type ON extracted_buildings (osm_type);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_wall ON extracted_buildings (wall);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_shelter_type ON extracted_buildings (shelter_type);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_building ON extracted_buildings (building);

\i insert_buildings_in_extracted_buildings.sql
----

\i add_triggers.sql


----
-- These views will be used to suggest the parent building of a way
----
CREATE MATERIALIZED VIEW osm_buildings_relation_links AS
SELECT
  r.id AS relation_id,
  CASE 
    WHEN substring(r.members[i] FROM 1 FOR 1) ='r' THEN (substring(r.members[i] FROM 2))::bigint *-1
    ELSE (substring(r.members[i] FROM 2))::bigint
  END AS member_id,
  substring(r.members[i] FROM 1 FOR 1)        AS member_type,
  r.members[i+1]                              AS role
FROM
  planet_osm_rels AS r
  JOIN LATERAL generate_series(
    1,
    array_length(r.members,1) - 1,
    2
  ) AS gs(i) ON true
WHERE
 (array_position(r.tags, 'building')   IS NOT NULL OR array_position(r.tags, 'building:part')   IS NOT NULL) ;


CREATE INDEX IF NOT EXISTS idx_osm_buildings_relation_links_ids_relation_id ON osm_buildings_relation_links(relation_id);
CREATE INDEX IF NOT EXISTS idx_osm_buildings_relation_links_ids_member_id ON osm_buildings_relation_links(member_id);

CREATE MATERIALIZED VIEW osm_buildings_outer_ways AS (
    SELECT
        member_id as osm_id,
        'planet_osm_polygon' as osm_table
    FROM
        osm_buildings_relation_links
        JOIN planet_osm_polygon p ON p.osm_id = member_id
    WHERE
        (
            p.tags ? 'building:part'
            AND p.tags -> 'building:part' != 'no'
        )
        OR (p.building NOT IN ('no', ''))
    UNION ALL
    SELECT
        member_id as osm_id,
        'planet_osm_line' as osm_table
    FROM
        osm_buildings_relation_links
        JOIN planet_osm_line l ON l.osm_id = member_id
    WHERE
        (
            (
                l.tags ? 'building:part'
                AND l.tags -> 'building:part' != 'no'
            )
            OR (l.building NOT IN ('no', ''))
        )
        AND ST_IsClosed(l.way)
        AND ST_NPoints(l.way) >= 4

);

CREATE INDEX IF NOT EXISTS idx_osm_buildings_outer_ways_osm_id ON osm_buildings_outer_ways(osm_id);
