# Boot Probe Report

| chapter | files | status | notes |
|---------|-------|--------|-------|
| chapter-01 | init.sql, seed.sql, queries.sql | ✓ | clean |
| chapter-02 | init.sql, seed.sql, mvcc-tour.sql | ✓ | clean |
| chapter-03 | init.sql, seed.sql, extensions.sql, storage-tour.sql | ✓ | clean |
| chapter-04 | init.sql, seed.sql, wal-tour.sql | ✓ | redo_tli fix already applied by prior agent |
| chapter-05 | init.sql, seed.sql, memory-tour.sql | ✓ | clean |
| chapter-06 | extensions.sql,index-tour.sql,init.sql,seed.sql | ✓ | added \ir extensions.sql + \ir init.sql + \ir seed.sql at top of index-tour.sql; demo runs clean |
| chapter-07 | init.sql,planner-tour.sql,seed.sql | ✓ | clean |
| chapter-08 | explain-walkthroughs.sql,init.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql at top of explain-walkthroughs.sql; demo runs clean |
| chapter-09 | indexing-tour.sql,init.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql; wrapped exclusion-constraint demo INSERT in BEGIN/SAVEPOINT/ROLLBACK/COMMIT block |
| chapter-10 | extensions.sql,init.sql,seed.sql,specialty-tour.sql | ✓ | clean |
| chapter-11 | init.sql,joins-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql at top of joins-tour.sql; demo runs clean |
| chapter-12 | init.sql,jsonb-tour.sql,seed.sql | ✓ | clean |
| chapter-13 | extensions.sql,fts-tour.sql,init.sql,seed.sql | ✓ | added \ir extensions.sql + \ir init.sql + \ir seed.sql at top of fts-tour.sql; demo runs clean |
| chapter-14 | init.sql,partitioning-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql; wrapped exclusion-constraint demo INSERT in BEGIN/SAVEPOINT/ROLLBACK/COMMIT; script completes clean |
| chapter-15 | init.sql,isolation-tour.sql,seed.sql | ✓ | clean |
| chapter-16 | concurrency-tour.sql,init.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql at top of concurrency-tour.sql; demo runs clean |
| chapter-17 | init.sql,queue-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql; commented out blocking LISTEN statements; demo runs clean |
| chapter-18 | extensions.sql,init.sql,seed.sql,vacuum-tour.sql | ✓ | clean |
| chapter-19 | init.sql,pooling-tour.sql,seed.sql | ✓ | clean |
| chapter-20 | extensions.sql,init.sql,monitoring-tour.sql,seed.sql | ✓ | Testcontainers container started with shared_preload_libraries=pg_stat_statements via withCommand; IT queries pg_stat_statements directly |
| chapter-21 | init.sql,migration-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql at top of migration-tour.sql; demo runs clean |
| chapter-22 | init.sql,replication-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql; wrapped pg_create_logical_replication_slot in DO/EXCEPTION (wal_level guard); cleanup uses conditional drop; demo runs clean |
| chapter-23 | init.sql,seed.sql,streaming-tour.sql | ✓ | added \ir init.sql + \ir seed.sql; added ROLLBACK after section (7) BEGIN so section (8) VACUUM runs outside transaction; demo runs clean |
| chapter-24 | init.sql,logical-tour.sql,seed.sql | ✓ | added \ir init.sql + \ir seed.sql; wrapped CREATE SUBSCRIPTION in DO/EXCEPTION to handle missing publisher gracefully; docker-compose.yml already present with pg15 publisher + pg17 subscriber |
| chapter-25 | init.sql,seed.sql | ✓ | clean |
| chapter-26 | init.sql,seed.sql | ✓ | clean |
| chapter-27 | init.sql,seed.sql,tuning-tour.sql | ✓ | clean |
| chapter-28 | init.sql,seed.sql | ✓ | clean |
