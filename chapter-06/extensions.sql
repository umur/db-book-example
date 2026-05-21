-- Extensions used by index-tour.sql.
-- pageinspect: low-level page and B-tree introspection (bt_metap, bt_page_stats).
-- pgstattuple: index density, fragmentation, dead-pointer accounting.
-- pg_visibility: per-page visibility map state (pg_visibility_map).

CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pgstattuple;
CREATE EXTENSION IF NOT EXISTS pg_visibility;
