-- Extensions used by the chapter-10 specialty index tour.
-- pg_trgm: trigram similarity for fuzzy text search (GIN and GiST).
-- bloom:    multi-column equality index for wide reporting tables.
-- btree_gist: lets GiST handle plain equality alongside range overlap,
--             needed by the EXCLUDE constraint on screen_bookings.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS bloom;
CREATE EXTENSION IF NOT EXISTS btree_gist;
