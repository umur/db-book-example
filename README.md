# PostgreSQL: From MVCC to Production

> The Postgres book a Spring Boot engineer actually needs — internals, query tuning, replication, partitioning, bloat, and the operational reality of running it.

Companion code for the book **PostgreSQL: From MVCC to Production** by [Umur Inan](https://umurinan.com).

## About the book

A Postgres book written for application engineers, not DBAs. Starts with MVCC and the buffer cache, walks through the query planner and EXPLAIN ANALYZE, covers indexes and bloat, full-text search and JSONB, partitioning and replication, pgbouncer and connection pooling, backups with pgBackRest, high availability with Patroni — every chapter grounded in a CinéTrack schema sized at MovieLens 25M for realistic measurement.

## Quick start

```bash
git clone https://github.com/umur/db-book-example
cd db-book-example/chapter-01
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f init.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
```

## Layout

One self-contained project per chapter:

- `chapter-01/ … chapter-28/` — each contains its own `docker-compose.yml` (Postgres, and later pgbouncer, replicas, Patroni, pgBackRest), an `init.sql`, a `seed.sql`, and a `queries.sql` of annotated examples

## Stack

- PostgreSQL 16
- Docker Compose for local orchestration
- pgbouncer (chapters on pooling)
- Patroni + etcd (chapters on HA)
- pgBackRest (chapters on backup and restore)
- pg_stat_statements, auto_explain, pgexperts/pgx_scripts (operational tooling)

## About the author

I'm Umur Inan. I write books about Spring Boot, Java, distributed systems, and the practices that make production reliable.

📚 **More writing and books → [umurinan.com](https://umurinan.com)**

## License

MIT — see [LICENSE](LICENSE).
