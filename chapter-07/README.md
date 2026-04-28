# Chapter 7 sandbox

A larger cinetrack dataset (50k movies, 500k ratings, 500k `view_events`
with correlated `country_code` and `language_code`) running against a
chapter-7 Postgres. The correlation between country and language is
the data shape that makes the extended-statistics walkthrough show a
real, before-and-after change in row estimates.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f planner-tour.sql
```

The seed step takes a minute or two. The view_events table holds
500,000 rows so the planner has to choose between scan strategies
that look genuinely different in cost.

## What to expect

Section (4) of `planner-tour.sql` runs a two-column filter on
correlated columns. The estimate is far below the actual row count.
Section (5) creates an extended statistics object, re-analyzes, and
re-runs the same query. The estimate snaps to within a few percent
of actual. That diff is the chapter's central evidence: the planner
is right when its inputs are right, and `CREATE STATISTICS` fixes
the input.

## Tear it down

```bash
docker compose down -v   # -v drops the volume
```
