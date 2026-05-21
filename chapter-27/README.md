# Chapter 27 sandbox

Postgres 17 running with the chapter's representative production-profile
config (`postgresql.conf.tuned`) plus a tour script that demonstrates the
effect of each major tuning knob on a real plan.

The bundled config assumes a host with at least 16 GB of free memory.
On a smaller laptop, override `shared_buffers` and `effective_cache_size`
on the `command:` block in `docker-compose.yml`, or comment those two
lines out of `postgresql.conf.tuned` and let the container fall back to
its built-in defaults. The tour will still demonstrate the same plan
changes; the absolute numbers will be smaller.

## Bring it up

```bash
docker compose up -d
psql -h localhost -U cinetrack -d cinetrack -f seed.sql
psql -h localhost -U cinetrack -d cinetrack -f tuning-tour.sql
```

The seed loads in 30 to 60 seconds. The tour runs in under a minute.

## What to watch

The tour file is annotated section by section. The most important
diffs to read in the output:

- Sections (2) vs (3): the `random_page_cost` flip changes the plan from
  sequential to index scan on `view_events`.
- Sections (4) vs (5): a wrong `effective_cache_size` changes the join
  order, even though no data is read differently.
- Sections (6) vs (7): `work_mem` flips the sort from `external merge`
  on disk to `quicksort` in memory.
- Section (10): `pg_buffercache` is the real answer to "is my working set
  in memory?"

## OS tuning

`os-tuning.sh` is for the host, not the container. Read the script first.
It writes to `/etc/sysctl.d`, `/etc/security/limits.d`, and
`/etc/udev/rules.d`, which is the right place to do this on a real
machine and the wrong place to do it in a container.

## Tear it down

```bash
docker compose down -v
```
