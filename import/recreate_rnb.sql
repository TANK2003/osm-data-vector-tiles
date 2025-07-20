--- delete all entries of extracted_buildings
DELETE FROM extracted_buildings;

---Insert buildings in extracted_buildings

\i ../sql/insert_buildings_in_extracted_buildings.sql


--- Recompute RNB matching

\i ./compute_rnb_matching.sql