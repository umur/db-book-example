# Chapter 3 sandbox

Same cinetrack starter, plus the storage-inspection extensions loaded on
startup: `pageinspect`, `pgstattuple`, and `pg_freespacemap`. The new file is
`storage-tour.sql`, ten annotated sections that walk through page headers,
line pointers, TOAST, free-space tracking, HOT versus non-HOT updates, and
the effect of fillfactor on a churning table.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f storage-tour.sql
```

## What to expect

`heap_page_items` shows you raw line pointers and tuple metadata, including
the MVCC fields from chapter 2. `pgstattuple` summarizes live versus dead
versus free space. The HOT update block raises `n_tup_hot_upd` proportional
to the churn. Once you `ALTER TABLE reviews SET (fillfactor = 80)` and
rewrite, the same churn produces a much higher HOT ratio.

## Tear it down

```bash
docker compose down -v   # -v drops the volume; next `up` starts fresh
```
