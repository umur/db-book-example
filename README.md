# PostgreSQL: From MVCC to Production

> The Postgres book a Spring Boot engineer actually needs: internals, query tuning, replication, partitioning, bloat, and the operational reality of running it.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white) ![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white) ![License: MIT](https://img.shields.io/badge/License%3A_MIT-MIT-blue)

Companion code for **PostgreSQL: From MVCC to Production** by [Umur Inan](https://umurinan.com).

## About the book

A Postgres book written for application engineers, not DBAs. Starts with MVCC and the buffer cache, walks through the query planner and EXPLAIN ANALYZE, covers indexes and bloat, full-text search and JSONB, partitioning and replication, pgbouncer and connection pooling, backups with pgBackRest, high availability with Patroni. Every chapter grounded in a CinéTrack schema sized at MovieLens 25M for realistic measurement.

## Who this is for

- Spring Boot engineers who write queries but have never read EXPLAIN ANALYZE
- Developers inheriting a Postgres schema with unexplained slowdowns, bloat, or replication lag
- Engineers moving toward DBA-adjacent responsibilities: backups, HA, connection pooling, schema migrations

## Chapters

1. The Postgres Way
2. MVCC, the Heart of Postgres
3. Storage: Pages, Tuples, TOAST, HOT
4. The Write-Ahead Log
5. Processes, Memory, and the Buffer Cache
6. Indexes from First Principles
7. The Planner and Statistics
8. Reading EXPLAIN
9. Index Strategies: B-tree
10. Specialty Indexes: GIN, GiST, BRIN, Hash
11. Joins and Query Rewriting
12. JSONB at Production Scale
13. Full-Text Search
14. Schema Design and Partitioning
15. Isolation and Locking
16. Concurrency Patterns
17. Queues and the Outbox
18. Vacuum, Bloat, and Wraparound
19. Connection Pooling
20. Monitoring and the Slow-Query Workflow
21. Zero-Downtime Schema Migrations
22. Replication Internals
23. Streaming Replication in Production
24. Logical Replication
25. High Availability with Patroni
26. Backups and Point-in-Time Recovery
27. Installing and Tuning Postgres
28. Capacity Planning and Production Runbooks

## Prerequisites

- Docker & Docker Compose
- psql client
- (HA chapters) etcd

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

- `chapter-01/ ... chapter-28/`: each contains its own `docker-compose.yml` (Postgres, and later pgbouncer, replicas, Patroni, pgBackRest), an `init.sql`, a `seed.sql`, and a `queries.sql` of annotated examples

## Stack

- PostgreSQL 16
- Docker Compose for local orchestration
- pgbouncer (chapters on pooling)
- Patroni + etcd (chapters on HA)
- pgBackRest (chapters on backup and restore)
- pg_stat_statements, auto_explain, pgexperts/pgx_scripts (operational tooling)

## Related books

- [Hibernate and Spring Data JPA in Depth](https://github.com/umur/hibernate-example): the Java side of the same persistence stack
- [Spring Boot 4 Performance in Practice](https://github.com/umur/spring-boot-performance-book-example): Chapters 19 to 22 cover the Spring Boot query tuning that this book approaches from the Postgres side
- [Microservices with Spring Boot 4](https://github.com/umur/microservices-example): database-per-service patterns and the schema design implications

## About the author

I'm Umur Inan. I write production-focused books about Java, Spring Boot, distributed systems, and everything that makes software reliable at scale.

[umurinan.com](https://umurinan.com)

## License

MIT. See [LICENSE](LICENSE).
