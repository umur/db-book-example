# Chapter 11 sandbox

Cinetrack sized for the joins tour: 50,000 movies, 10,000 users,
500,000 ratings, 50,000 reviews, 200,000 view events. Big enough that
nested loop versus hash join produces visibly different runtimes;
small enough to run on a laptop.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f joins-tour.sql
```

The tour is twelve numbered sections covering nested loop versus hash
join selectivity, `EXISTS` versus `IN` versus `JOIN DISTINCT`,
`LATERAL` for top-N-per-group, the CTE optimization fence with
`MATERIALIZED` and `NOT MATERIALIZED`, a window function for running
totals, a materialized view for a hot aggregate, and a planner-misjudges
case fixed first by `ANALYZE` and then by a pre-join rewrite.

## What to expect

`EXPLAIN (ANALYZE, BUFFERS)` runs throughout the tour. Watch the join
algorithm flip between Nested Loop, Hash Join, and Merge Join based on
row counts. Watch the row estimate and the actual row count diverge in
section 10 and converge in section 11. The numbers are what the chapter
prose asserts; here you see them on your own machine.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
