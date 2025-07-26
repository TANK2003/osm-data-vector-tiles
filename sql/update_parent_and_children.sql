UPDATE
    extracted_buildings
SET
    parent_and_children = subquery.parent_outer_way
FROM
    (
        SELECT
            eb.osm_id,
            matched_members.parent_outer_way
        FROM
            extracted_buildings eb
            JOIN (
                SELECT
                    r1.member_id,
                    array_agg(r2.role) AS roles,
                    jsonb_agg(
                        json_build_object('osm_id', r2.member_id, 'role', r2.role)
                    ) AS parent_outer_way
                FROM
                    osm_buildings_relation_links r1
                    JOIN osm_buildings_relation_links r2 ON r1.relation_id = r2.relation_id
                    JOIN osm_buildings_outer_ways ON osm_buildings_outer_ways.osm_id = r2.member_id
                WHERE
                    r1.role != 'outer'
                GROUP BY
                    r1.member_id
            ) matched_members ON eb.osm_id = matched_members.member_id
        WHERE
            eb.osm_type = 'way'
            AND (
                array_position(matched_members.roles, 'outer') is not null
                OR array_position(matched_members.roles, 'outline') is not null
            )
    ) as subquery
WHERE
    extracted_buildings.osm_id = subquery.osm_id;
