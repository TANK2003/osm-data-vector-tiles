CREATE INDEX IF NOT EXISTS idx_tags_hstore_gin ON public.planet_osm_polygon USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_line_tags_hstore_gin ON public.planet_osm_line USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_planet_osm_rels_members_gin ON planet_osm_rels USING GIN (members);


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

CREATE INDEX IF NOT EXISTS idx_extracted_buildings_way ON extracted_buildings USING GIST (way);

CREATE INDEX IF NOT EXISTS idx_extracted_buildings_osm_id ON extracted_buildings (osm_id);

CREATE INDEX IF NOT EXISTS idx_extracted_buildings_osm_type ON extracted_buildings (osm_type);


\i insert_buildings_in_extracted_buildings.sql
----

CREATE OR REPLACE FUNCTION trg_update_rnb_fields()
RETURNS trigger AS
$$
BEGIN
  IF EXISTS (
       SELECT 1
         FROM extracted_buildings cb
        WHERE cb.osm_id = NEW.osm_id
     ) THEN
    UPDATE extracted_buildings SET
      rnb      = COALESCE(NEW.tags -> 'ref:FR:RNB', ''),      
      diff_rnb =COALESCE(NEW.tags -> 'diff:ref:FR:RNB', '') 
    WHERE osm_id = NEW.osm_id;
  END IF;

  RETURN NULL;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_custom_rnb_poly
  ON planet_osm_polygon;

DROP TRIGGER IF EXISTS update_custom_rnb_poly
  ON planet_osm_line;

CREATE TRIGGER  update_custom_rnb_poly
  AFTER INSERT OR UPDATE
  ON planet_osm_polygon
  FOR EACH ROW
  EXECUTE FUNCTION trg_update_rnb_fields();

CREATE TRIGGER  update_custom_rnb_line
  AFTER INSERT OR UPDATE
  ON planet_osm_line
  FOR EACH ROW
  EXECUTE FUNCTION trg_update_rnb_fields();

-----
UPDATE
    extracted_buildings
SET
    ombb00 = sub.ombb00,
    ombb01 = sub.ombb01,
    ombb10 = sub.ombb10,
    ombb11 = sub.ombb11,
    ombb20 = sub.ombb20,
    ombb21 = sub.ombb21,
    ombb30 = sub.ombb30,
    ombb31 = sub.ombb31
FROM
    (
        SELECT
            id,
            ST_X(ST_PointN(ring, 1)) AS ombb00,
            ST_Y(ST_PointN(ring, 1)) AS ombb01,
            ST_X(ST_PointN(ring, 2)) AS ombb10,
            ST_Y(ST_PointN(ring, 2)) AS ombb11,
            ST_X(ST_PointN(ring, 3)) AS ombb20,
            ST_Y(ST_PointN(ring, 3)) AS ombb21,
            ST_X(ST_PointN(ring, 4)) AS ombb30,
            ST_Y(ST_PointN(ring, 4)) AS ombb31
        FROM
            (
                SELECT
                    id,
                    ST_ExteriorRing(ST_OrientedEnvelope(ST_Transform(way, 3857))) AS ring
                FROM
                    extracted_buildings
            ) AS inner_sub
    ) AS sub
WHERE
    sub.id = extracted_buildings.id;