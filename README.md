# PostgreSQL: From MVCC to Production

> PostgreSQL 17 from MVCC up. For engineers who can read EXPLAIN and need to read it better.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white) ![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white) ![SQL](https://img.shields.io/badge/Pure-SQL-336791?logo=postgresql&logoColor=white) ![License: MIT](https://img.shields.io/badge/License%3A_MIT-MIT-blue)

Companion code for **PostgreSQL: From MVCC to Production** by [Umur Inan](https://umurinan.com).

## About the book

Twenty-eight chapters on Postgres 17 in pure SQL. No Spring, no JPA, no Hibernate in the way. The book opens with MVCC and tuple visibility because every other Postgres production mystery traces back to it: long-running transactions blocking vacuum, dead tuples bloating tables, replicas falling behind, deadlocks at 3 AM. The CinéTrack movie domain seeded from MovieLens 25M runs through every chapter, with a synthesized 100M-row `view_events` table for the partitioning and BRIN demos.

## Who this is for

- Senior backend engineers who write SQL every day and need to write it better
- Platform and database engineers running Postgres in production and tuning the operational dials
- Engineers moving toward DBA-adjacent responsibilities: vacuum, replication, HA, backups, schema migrations

## Prerequisites

- Docker and Docker Compose
- The `psql` client
- Working SQL: joins, subqueries, GROUP BY, and the ability to read an EXPLAIN plan
- etcd (for the HA chapters with Patroni)

## Quick start

```bash
git clone https://github.com/umur/postgres-example
cd postgres-example/chapter-01
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f schema.sql
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
```

## Chapters

Each `chapter-NN/` directory is a self-contained Docker Compose stack with its own `schema.sql`, `seed.sql`, and `queries.sql` of annotated examples. Later chapters add pgbouncer, streaming replicas, Patroni plus etcd, and pgBackRest as separate services.

- `chapter-01`: The Postgres Way: MVCC bet, process-per-connection model, extensibility.
- `chapter-02`: MVCC at the tuple level: xmin, xmax, visibility, the update illusion.
- `chapter-03`: Storage internals: 8KB pages, tuple anatomy, TOAST, HOT updates.
- `chapter-04`: The write-ahead log: WAL records, LSN, full-page writes, checkpoints, fsync.
- `chapter-05`: Processes, shared memory, the buffer cache, per-backend memory cost.
- `chapter-06`: Indexes from first principles: B-tree internals, index-only scans, MVCC and indexes.
- `chapter-07`: The planner and statistics: cost model, pg_statistic, extended statistics, planner knobs.
- `chapter-08`: Reading EXPLAIN: ANALYZE, BUFFERS, join nodes, finding the bottleneck.
- `chapter-09`: B-tree index strategies: multi-column, partial, expression, covering with INCLUDE.
- `chapter-10`: Specialty indexes: GIN, GiST, BRIN, Hash, Bloom, and when to pick each.
- `chapter-11`: Joins and query rewriting: nested loop, hash, merge, join order, CTEs.
- `chapter-12`: JSONB at production scale: operators, GIN indexes, JSONB vs relational design.
- `chapter-13`: Full-text search: tsvector, tsquery, ranking, trigram, when FTS is enough.
- `chapter-14`: Schema design and declarative partitioning: partitioning `view_events` by month.
- `chapter-15`: Isolation and locking: Read Committed, Repeatable Read, SSI, row and table locks.
- `chapter-16`: Concurrency patterns: SELECT FOR UPDATE SKIP LOCKED, advisory locks, OCC, upserts.
- `chapter-17`: Queues and the outbox: SKIP LOCKED job queues, transactional outbox, LISTEN/NOTIFY.
- `chapter-18`: Vacuum, bloat, and wraparound: autovacuum internals, bloat recovery, freezing.
- `chapter-19`: Connection pooling: pgbouncer modes, prepared statements, pool sizing.
- `chapter-20`: Monitoring and the slow-query workflow: pg_stat_statements, auto_explain, pg_stat_io.
- `chapter-21`: Zero-downtime schema migrations: lock_timeout, safe ADD COLUMN, concurrent indexes.
- `chapter-22`: Replication internals: physical vs logical, WAL streaming, slots, synchronous vs async.
- `chapter-23`: Streaming replication in production: replica setup, lag, cascading, vacuum conflicts.
- `chapter-24`: Logical replication: publications, subscriptions, row filters, major-version upgrades.
- `chapter-25`: High availability with Patroni: leader election, fencing, split-brain prevention.
- `chapter-26`: Backups and PITR: pgBackRest, point-in-time recovery, recovery testing.
- `chapter-27`: Installing and tuning Postgres: postgresql.conf tour, OS-level tuning, hardware sizing.
- `chapter-28`: Capacity planning and runbooks: disk full, replication broke, vacuum can't keep up.

## Stack

- PostgreSQL 17 (primary target, PG 15 and 16 callouts where behavior differs materially)
- Pure SQL: no Spring, JDBC, JPA, or Hibernate code
- Docker Compose per chapter (Postgres-only, plus `schema.sql` and `seed.sql`)
- pgbouncer (chapters on connection pooling)
- Patroni and etcd (chapters on HA)
- pgBackRest (chapters on backup and point-in-time recovery)
- pg_stat_statements, auto_explain, pgexperts/pgx_scripts (operational tooling)

## Related books

- [Hibernate and Spring Data JPA in Depth](https://github.com/umur/hibernate-spring-data-example): the Java side of the same persistence stack.
- [Spring Boot Performance](https://github.com/umur/spring-boot-performance-example): the Spring Boot query tuning that this book approaches from the Postgres side.
- [Microservices with Spring Boot 4](https://github.com/umur/microservices-example): database-per-service patterns and the schema design implications.

## About the author

I'm Umur Inan, a Principal Software Engineer with 15 years of experience building backend systems across enterprise, government, and high-growth environments. I specialize in microservices architecture, distributed systems, and cloud-native development, with deep expertise in Spring Boot, Kafka, and Kubernetes. Based in New York City, I've shipped products across five countries and hold a Master's in Computer Science and a Bachelor's in Computer Engineering.

[umurinan.com](https://umurinan.com)

## License

MIT. See [LICENSE](LICENSE).
