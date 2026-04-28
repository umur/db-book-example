-- Chapter 20 extensions.
-- pg_stat_statements is the workhorse. pg_buffercache is for the
-- "what's in cache right now" query in section 20.7.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
