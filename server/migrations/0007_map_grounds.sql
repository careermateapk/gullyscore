-- v0.9: cricket grounds read from OpenStreetMap (free) near where people search.
-- Map grounds sit in the grounds table with place_id 'osm:<type>/<id>' and no owner
-- until someone fills in their details.
CREATE TABLE IF NOT EXISTS map_areas (
  area TEXT PRIMARY KEY,   -- rounded lat,lng + radius that was looked up
  fetched INTEGER NOT NULL
);
