CREATE MATERIALIZED VIEW osm_relation_links AS
SELECT
  r.id AS relation_id,
  (substring(r.members[i] FROM 2))::bigint    AS member_id,
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
 array_position(r.tags, 'building')   IS NOT NULL AND
  (array_position(r.members, 'outline')   IS NOT NULL);


CREATE INDEX IF NOT EXISTS idx_osm_relation_links_ids_relation_id ON osm_relation_links(relation_id);
CREATE INDEX IF NOT EXISTS idx_osm_relation_links_ids_member_id ON osm_relation_links(member_id);


CREATE MATERIALIZED VIEW outline_way_ids AS
WITH RECURSIVE
  outline_roots AS (
    SELECT relation_id, member_id, member_type
    FROM osm_relation_links
    WHERE role IN ('outer','outline')
  ),
  outline_descendants AS (
    -- 1) on démarre sur les “roots”
    SELECT member_id, member_type
    FROM outline_roots
    UNION ALL
    -- 2) on descend récursivement pour toutes les relations
    SELECT
      l.member_id,
      l.member_type
    FROM osm_relation_links l
    JOIN outline_descendants od
      ON l.relation_id = od.member_id
    WHERE od.member_type = 'r'
  )
SELECT DISTINCT member_id AS way_id
FROM outline_descendants
WHERE member_type = 'w'
;

CREATE INDEX ON outline_way_ids(way_id);




