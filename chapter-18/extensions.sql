-- Extensions used by the chapter-18 tour.
--
-- pgstattuple gives exact bloat measurement on a relation by reading every
-- page. pg_visibility lets us inspect the visibility map (used for index-only
-- scans and aggressive freezing).
--
-- Both are contrib extensions shipped with the postgres image. They are not
-- enabled by default; we enable them explicitly here.

CREATE EXTENSION IF NOT EXISTS pgstattuple;
CREATE EXTENSION IF NOT EXISTS pg_visibility;

-- Verify extensions are available.
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pgstattuple', 'pg_visibility')
ORDER BY extname;
