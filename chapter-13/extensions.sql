-- Chapter 13 extensions.
-- pg_trgm provides trigram-similarity operators and the gin_trgm_ops index
-- operator class used by the fuzzy-fallback path in the chapter.
-- Loaded by docker-entrypoint before init.sql so the chapter's GIN trigram
-- indexes can be created in init.sql.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
