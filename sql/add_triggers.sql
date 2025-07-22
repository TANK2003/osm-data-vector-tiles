CREATE
OR REPLACE FUNCTION trg_sync_buildings() RETURNS trigger AS $$ BEGIN
IF (
  TG_OP = 'INSERT'
  OR TG_OP = 'UPDATE'
) THEN IF (
  (
    NOT (
      NEW.tags ? 'location'
      AND NEW.tags -> 'location' != ''
      AND (
        NEW.tags -> 'location' ~ '^-?[0-9]+(\.[0-9]+)?$'
        AND (NEW.tags -> 'location') :: float < 0
      )
    )
    AND NOT COALESCE(NEW.tags -> 'tunnel', 'no') != 'no'
    AND NOT COALESCE(NEW.tags -> 'location', 'underground') != 'underground'
    AND NOT COALESCE(NEW.tags -> 'parking', 'underground') != 'underground'
  )
  AND (
    (
      NEW.tags ? 'building:part'
      and NEW.tags -> 'building:part' != 'no'
    )
    OR (NEW.building not in ('no', ''))
  )
  AND(
    st_geometrytype(NEW.way) in ('ST_Polygon','ST_MultiPolygon')
    OR (
        ST_IsClosed(NEW.way)
        AND ST_NPoints(NEW.way) >= 4
    )
  )
  AND (
    NOT EXISTS(
    SELECT
        1
    from
        outline_way_ids
    where
        way_id = NEW.osm_id
    )
  )
) THEN IF (
  NOT EXISTS (
    SELECT
      1
    FROM
      extracted_buildings cb
    WHERE
      cb.osm_id = NEW.osm_id
  )
) THEN
INSERT INTO
  extracted_buildings (
    osm_id,
    osm_type,
    type,
    is_part,
    building,
    wall,
    building_type,
    name,
    height,
    min_height,
    levels,
    min_level,
    material,
    roof_height,
    roof_levels,
    roof_material,
    roof_type,
    roof_orientation,
    roof_direction,
    roof_color,
    color,
    windows,
    default_roof,
    rnb,
    diff_rnb,
    shelter_type,
    way
  )
VALUES
(
    NEW.osm_id,
    CASE
      WHEN NEW.osm_id > 0 THEN 'way'
      WHEN NEW.osm_id < 0 THEN 'relation'
      ELSE null
    END ,
    'building' ,
    NEW.tags ? 'building:part' ,
    NEW.building ,
    NEW.tags -> 'wall' ,
    COALESCE(NEW.tags -> 'building:part', NEW.building) ,
    NEW.name,
    CASE
      WHEN NEW.tags ? 'height'
      AND NEW.tags -> 'height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'height') :: float
      ELSE NULL
    END ,
    CASE
      WHEN NEW.tags ? 'min_height'
      AND NEW.tags -> 'min_height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'min_height') :: float
      ELSE NULL
    END ,
    CASE
      WHEN NEW.tags ? 'building:levels'
      AND NEW.tags -> 'building:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'building:levels') :: float :: int
      ELSE NULL
    END ,
    CASE
      WHEN NEW.tags ? 'building:min_level'
      AND NEW.tags -> 'building:min_level' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'building:min_level') :: float :: int
      ELSE NULL
    END ,
    COALESCE((NEW.tags -> 'building:material'), '') ,
    CASE
      WHEN NEW.tags ? 'roof:height'
      AND NEW.tags -> 'roof:height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'roof:height') :: float
      ELSE NULL
    END ,
    CASE
      WHEN NEW.tags ? 'roof:levels'
      AND NEW.tags -> 'roof:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'roof:levels') :: float :: int
      ELSE NULL
    END ,
    COALESCE((NEW.tags -> 'roof:material'), '') ,
    COALESCE((NEW.tags -> 'roof:shape'), '') ,
    CASE
      WHEN COALESCE((NEW.tags -> 'roof:orientation'), '') IN ('along', 'across') THEN NEW.tags -> 'roof:orientation'
      ELSE NULL
    END ,
    CASE
      UPPER(NEW.tags -> 'roof:direction')
      WHEN 'N' THEN 0.0
      WHEN 'NNE' THEN 22.5
      WHEN 'NE' THEN 45.0
      WHEN 'ENE' THEN 67.5
      WHEN 'E' THEN 90.0
      WHEN 'ESE' THEN 112.5
      WHEN 'SE' THEN 135.0
      WHEN 'SSE' THEN 157.5
      WHEN 'S' THEN 180.0
      WHEN 'SSW' THEN 202.5
      WHEN 'SW' THEN 225.0
      WHEN 'WSW' THEN 247.5
      WHEN 'W' THEN 270.0
      WHEN 'WNW' THEN 292.5
      WHEN 'NW' THEN 315.0
      WHEN 'NNW' THEN 337.5
      ELSE NULL
    END ,
    trim(split_part(NEW.tags -> 'roof:colour', ';', 1)) ,
    trim(
      split_part(NEW.tags -> 'building:colour', ';', 1)
    ) ,
    CASE
      WHEN COALESCE((NEW.tags -> 'windows'), '') NOT IN ('', 'no') THEN NEW.tags -> 'windows'
      ELSE NULL
    END ,
    CASE
      WHEN (
        NOT NEW.tags ? 'bridge:support'
        OR NOT NEW.tags ? 'ship:type'
        OR NOT (
          NEW.tags ?| ARRAY ['man_made', 'storage_tank', 'chimney', 'stele']
        )
      ) Then false
      Else NULL
    END ,
    COALESCE(NEW.tags -> 'ref:FR:RNB', '') ,
    COALESCE(NEW.tags -> 'diff:ref:FR:RNB', '') ,
    NEW.tags -> 'shelter_type' ,
    CASE
        WHEN st_geometrytype(NEW.way) in ('ST_Polygon','ST_MultiPolygon') THEN ST_Transform(NEW.way, 4326)
        ELSE ST_MakePolygon(ST_Transform(NEW.way, 4326))
    END
    
  );

ELSE
UPDATE
  extracted_buildings
SET
    osm_type = CASE
      WHEN NEW.osm_id > 0 THEN 'way'
      WHEN NEW.osm_id < 0 THEN 'relation'
      ELSE null
    END,
    type = 'building',
    is_part = NEW.tags ? 'building:part',
    building = NEW.building,
    wall = NEW.tags -> 'wall',
    building_type = COALESCE(NEW.tags -> 'building:part', NEW.building),
    name = NEW.name,
    height = CASE
      WHEN NEW.tags ? 'height'
      AND NEW.tags -> 'height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'height') :: float
      ELSE NULL
    END,
    min_height = CASE
      WHEN NEW.tags ? 'min_height'
      AND NEW.tags -> 'min_height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'min_height') :: float
      ELSE NULL
    END,
    levels = CASE
      WHEN NEW.tags ? 'building:levels'
      AND NEW.tags -> 'building:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'building:levels') :: float :: int
      ELSE NULL
    END,
    min_level =CASE
      WHEN NEW.tags ? 'building:min_level'
      AND NEW.tags -> 'building:min_level' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'building:min_level') :: float :: int
      ELSE NULL
    END,
    material = COALESCE((NEW.tags -> 'building:material'), ''),
    roof_height =CASE
      WHEN NEW.tags ? 'roof:height'
      AND NEW.tags -> 'roof:height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'roof:height') :: float
      ELSE NULL
    END,
    roof_levels = CASE
      WHEN NEW.tags ? 'roof:levels'
      AND NEW.tags -> 'roof:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (NEW.tags -> 'roof:levels') :: float :: int
      ELSE NULL
    END,
    roof_material = COALESCE((NEW.tags -> 'roof:material'), ''),
    roof_type = COALESCE((NEW.tags -> 'roof:shape'), ''),
    roof_orientation = CASE
      WHEN COALESCE((NEW.tags -> 'roof:orientation'), '') IN ('along', 'across') THEN NEW.tags -> 'roof:orientation'
      ELSE NULL
    END,
    roof_direction = CASE
      UPPER(NEW.tags -> 'roof:direction')
      WHEN 'N' THEN 0.0
      WHEN 'NNE' THEN 22.5
      WHEN 'NE' THEN 45.0
      WHEN 'ENE' THEN 67.5
      WHEN 'E' THEN 90.0
      WHEN 'ESE' THEN 112.5
      WHEN 'SE' THEN 135.0
      WHEN 'SSE' THEN 157.5
      WHEN 'S' THEN 180.0
      WHEN 'SSW' THEN 202.5
      WHEN 'SW' THEN 225.0
      WHEN 'WSW' THEN 247.5
      WHEN 'W' THEN 270.0
      WHEN 'WNW' THEN 292.5
      WHEN 'NW' THEN 315.0
      WHEN 'NNW' THEN 337.5
      ELSE NULL
    END,
    roof_color = trim(split_part(NEW.tags -> 'roof:colour', ';', 1)),
    color = trim(
      split_part(NEW.tags -> 'building:colour', ';', 1)
    ),
    windows = CASE
      WHEN COALESCE((NEW.tags -> 'windows'), '') NOT IN ('', 'no') THEN NEW.tags -> 'windows'
      ELSE NULL
    END,
    default_roof = CASE
      WHEN (
        NOT NEW.tags ? 'bridge:support'
        OR NOT NEW.tags ? 'ship:type'
        OR NOT (
          NEW.tags ?| ARRAY ['man_made', 'storage_tank', 'chimney', 'stele']
        )
      ) Then false
      Else NULL
    END,
    rnb = COALESCE(NEW.tags -> 'ref:FR:RNB', ''),
    diff_rnb = COALESCE(NEW.tags -> 'diff:ref:FR:RNB', ''),
    shelter_type = NEW.tags -> 'shelter_type',
    way = ST_Transform(NEW.way, 4326)
WHERE
  osm_id = NEW.osm_id;

END IF;

ELSE -- Si ce n'est plus un bâtiment, on supprime
DELETE FROM
  extracted_buildings
WHERE
  osm_id = NEW.osm_id;

END IF;

-- Sur DELETE : on retire le bâtiment supprimé
ELSIF (TG_OP = 'DELETE') THEN
DELETE FROM
  extracted_buildings
WHERE
  osm_id = OLD.osm_id;

END IF;

RETURN NULL;

-- trigger AFTER
END;

$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS update_custom_rnb_poly
  ON planet_osm_polygon;
CREATE TRIGGER  update_custom_rnb_poly
  AFTER INSERT OR UPDATE OR DELETE
  ON planet_osm_polygon
  FOR EACH ROW
  EXECUTE FUNCTION trg_sync_buildings();

DROP TRIGGER IF EXISTS update_custom_rnb_line
  ON planet_osm_line;

CREATE TRIGGER  update_custom_rnb_line
  AFTER INSERT OR UPDATE OR DELETE
  ON planet_osm_line
  FOR EACH ROW
  EXECUTE FUNCTION trg_sync_buildings();