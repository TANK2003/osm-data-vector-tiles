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
    ) WITH RECURSIVE -- 1) relation_links : chaque relation dépliée en (relation→membre, rôle)
    relation_links AS (
        SELECT
            r.id AS relation_id,
            (m ->> 'ref') :: bigint AS member_id,
            m ->> 'type' AS member_type,
            -- 'W' ou 'R'
            m ->> 'role' AS role
        FROM
            planet_osm_rels r
            CROSS JOIN LATERAL jsonb_array_elements(to_jsonb(r.members)) AS m
    ),
    -- 2) outline_roots : graine = **tous** les liens (W ou R) ayant rôle outer/outline
    outline_roots AS (
        SELECT
            relation_id,
            member_id,
            member_type
        FROM
            relation_links
        WHERE
            role IN ('outer', 'outline')
    ),
    -- 3) outline_descendants : descente récursive depuis ces graines
    outline_descendants AS (
        -- a) on part des graines (ways et relations marqués outer/outline)
        SELECT
            member_id,
            member_type
        FROM
            outline_roots
        UNION
        ALL -- b) on descend : si un descendant est une relation, on prend ses membres
        SELECT
            rl.member_id,
            rl.member_type
        FROM
            relation_links rl
            JOIN outline_descendants od ON rl.relation_id = od.member_id
        WHERE
            od.member_type = 'R'
    ),
    -- 4) on filtre pour ne garder que les ways rencontrés
    ways_used_as_outline AS (
        SELECT
            DISTINCT member_id AS way_id
        FROM
            outline_descendants
        WHERE
            member_type = 'W'
    )
SELECT
    p.osm_id,
    CASE
        WHEN p.osm_id > 0 THEN 'way'
        WHEN p.osm_id < 0 THEN 'relation'
        ELSE null
    END AS osm_type,
    'building' as type,
    p.tags ? 'building:part' as is_part,
    p.building as building,
    p.tags -> 'wall' as wall,
    COALESCE(p.tags -> 'building:part', building) as building_type,
    name,
    CASE
        WHEN p.tags ? 'height'
        AND p.tags -> 'height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'height') :: float
        ELSE NULL
    END AS height,
    CASE
        WHEN p.tags ? 'min_height'
        AND p.tags -> 'min_height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'min_height') :: float
        ELSE NULL
    END AS min_height,
    CASE
        WHEN p.tags ? 'building:levels'
        AND p.tags -> 'building:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'building:levels') :: float :: int
        ELSE NULL
    END AS levels,
    CASE
        WHEN p.tags ? 'building:min_level'
        AND p.tags -> 'building:min_level' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'building:min_level') :: float :: int
        ELSE NULL
    END AS min_level,
    COALESCE((p.tags -> 'building:material'), '') AS material,
    CASE
        WHEN p.tags ? 'roof:height'
        AND p.tags -> 'roof:height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'roof:height') :: float
        ELSE NULL
    END AS roof_height,
    CASE
        WHEN p.tags ? 'roof:levels'
        AND p.tags -> 'roof:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'roof:levels') :: float :: int
        ELSE NULL
    END AS roof_levels,
    COALESCE((p.tags -> 'roof:material'), '') AS roof_material,
    COALESCE((p.tags -> 'roof:shape'), '') AS roof_type,
    CASE
        WHEN COALESCE((p.tags -> 'roof:orientation'), '') IN ('along', 'across') THEN p.tags -> 'roof:orientation'
        ELSE NULL
    END AS roof_orientation,
    CASE
        UPPER(p.tags -> 'roof:direction')
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
    END AS roof_direction,
    trim(split_part(p.tags -> 'roof:colour', ';', 1)) AS roof_color,
    trim(split_part(p.tags -> 'building:colour', ';', 1)) AS color,
    CASE
        WHEN COALESCE((p.tags -> 'windows'), '') NOT IN ('', 'no') THEN p.tags -> 'windows'
        ELSE NULL
    END AS roof_orientation,
    CASE
        WHEN (
            NOT p.tags ? 'bridge:support'
            OR NOT p.tags ? 'ship:type'
            OR NOT (
                p.tags ?| ARRAY ['man_made', 'storage_tank', 'chimney', 'stele']
            )
        ) Then false
        Else NULL
    END AS default_roof,
    COALESCE(p.tags -> 'ref:FR:RNB', '') as rnb,
    COALESCE(p.tags -> 'diff:ref:FR:RNB', '') as diff_rnb,
    p.tags -> 'shelter_type' as shelter_type,
    ST_Transform(p.way, 4326) as way
FROM
    public.planet_osm_polygon p
WHERE
    osm_id NOT IN (
        SELECT
            way_id
        FROM
            ways_used_as_outline
    )
    AND (
        NOT (
            p.tags ? 'location'
            AND p.tags -> 'location' != ''
            AND (
                p.tags -> 'location' ~ '^-?[0-9]+(\.[0-9]+)?$'
                AND (p.tags -> 'location') :: float < 0
            )
        )
        AND NOT COALESCE(p.tags -> 'tunnel', 'no') != 'no'
        AND NOT COALESCE(p.tags -> 'location', 'underground') != 'underground'
        AND NOT COALESCE(p.tags -> 'parking', 'underground') != 'underground'
    )
    AND (
        (
            p.tags ? 'building:part'
            and p.tags -> 'building:part' != 'no'
        )
        OR (p.building not in ('no', ''))
    );

-----
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
    ) WITH RECURSIVE -- 1) relation_links : chaque relation dépliée en (relation→membre, rôle)
    relation_links AS (
        SELECT
            r.id AS relation_id,
            (m ->> 'ref') :: bigint AS member_id,
            m ->> 'type' AS member_type,
            m ->> 'role' AS role
        FROM
            planet_osm_rels r
            CROSS JOIN LATERAL jsonb_array_elements(to_jsonb(r.members)) AS m
    ),
    -- 2) outline_roots : graine = **tous** les liens (W ou R) ayant rôle outer/outline
    outline_roots AS (
        SELECT
            relation_id,
            member_id,
            member_type
        FROM
            relation_links
        WHERE
            role IN ('outer', 'outline')
    ),
    -- 3) outline_descendants : descente récursive depuis ces graines
    outline_descendants AS (
        -- a) on part des graines (ways et relations marqués outer/outline)
        SELECT
            member_id,
            member_type
        FROM
            outline_roots
        UNION
        ALL -- b) on descend : si un descendant est une relation, on prend ses membres
        SELECT
            rl.member_id,
            rl.member_type
        FROM
            relation_links rl
            JOIN outline_descendants od ON rl.relation_id = od.member_id
        WHERE
            od.member_type = 'R'
    ),
    -- 4) on filtre pour ne garder que les ways rencontrés
    ways_used_as_outline AS (
        SELECT
            DISTINCT member_id AS way_id
        FROM
            outline_descendants
        WHERE
            member_type = 'W'
    )
SELECT
    p.osm_id,
    CASE
        WHEN p.osm_id > 0 THEN 'way'
        WHEN p.osm_id < 0 THEN 'relation'
        ELSE null
    END AS osm_type,
    'building' as type,
    p.tags ? 'building:part' as is_part,
    p.building as building,
    p.tags -> 'wall' as wall,
    COALESCE(p.tags -> 'building:part', building) as building_type,
    name,
    CASE
        WHEN p.tags ? 'height'
        AND p.tags -> 'height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'height') :: float
        ELSE NULL
    END AS height,
    CASE
        WHEN p.tags ? 'min_height'
        AND p.tags -> 'min_height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'min_height') :: float
        ELSE NULL
    END AS min_height,
    CASE
        WHEN p.tags ? 'building:levels'
        AND p.tags -> 'building:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'building:levels') :: float :: int
        ELSE NULL
    END AS levels,
    CASE
        WHEN p.tags ? 'building:min_level'
        AND p.tags -> 'building:min_level' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'building:min_level') :: float :: int
        ELSE NULL
    END AS min_level,
    COALESCE((p.tags -> 'building:material'), '') AS material,
    CASE
        WHEN p.tags ? 'roof:height'
        AND p.tags -> 'roof:height' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'roof:height') :: float
        ELSE NULL
    END AS roof_height,
    CASE
        WHEN p.tags ? 'roof:levels'
        AND p.tags -> 'roof:levels' ~ '^[0-9]+(\.[0-9]+)?$' THEN (p.tags -> 'roof:levels') :: float :: int
        ELSE NULL
    END AS roof_levels,
    COALESCE((p.tags -> 'roof:material'), '') AS roof_material,
    COALESCE((p.tags -> 'roof:shape'), '') AS roof_type,
    CASE
        WHEN COALESCE((p.tags -> 'roof:orientation'), '') IN ('along', 'across') THEN p.tags -> 'roof:orientation'
        ELSE NULL
    END AS roof_orientation,
    CASE
        UPPER(p.tags -> 'roof:direction')
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
    END AS roof_direction,
    trim(split_part(p.tags -> 'roof:colour', ';', 1)) AS roof_color,
    trim(split_part(p.tags -> 'building:colour', ';', 1)) AS color,
    CASE
        WHEN COALESCE((p.tags -> 'windows'), '') NOT IN ('', 'no') THEN p.tags -> 'windows'
        ELSE NULL
    END AS roof_orientation,
    CASE
        WHEN (
            NOT p.tags ? 'bridge:support'
            OR NOT p.tags ? 'ship:type'
            OR NOT (
                p.tags ?| ARRAY ['man_made', 'storage_tank', 'chimney', 'stele']
            )
        ) Then false
        Else NULL
    END AS default_roof,
    COALESCE(p.tags -> 'ref:FR:RNB', '') as rnb,
    COALESCE(p.tags -> 'diff:ref:FR:RNB', '') as diff_rnb,
    p.tags -> 'shelter_type' as shelter_type,
    ST_MakePolygon(ST_Transform(p.way, 4326)) as way
FROM
    public.planet_osm_line p
WHERE
    osm_id NOT IN (
        SELECT
            way_id
        FROM
            ways_used_as_outline
    )
    AND ST_IsClosed(way)
    AND ST_NPoints(way) >= 4
    AND (
        NOT (
            p.tags ? 'location'
            AND p.tags -> 'location' != ''
            AND (
                p.tags -> 'location' ~ '^-?[0-9]+(\.[0-9]+)?$'
                AND (p.tags -> 'location') :: float < 0
            )
        )
        AND NOT COALESCE(p.tags -> 'tunnel', 'no') != 'no'
        AND NOT COALESCE(p.tags -> 'location', 'underground') != 'underground'
        AND NOT COALESCE(p.tags -> 'parking', 'underground') != 'underground'
    )
    AND (
        (
            p.tags ? 'building:part'
            and p.tags -> 'building:part' != 'no'
        )
        OR (p.building not in ('no', ''))
    );
