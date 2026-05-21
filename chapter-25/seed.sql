-- Minimal seed data. Three movies, three users, three reviews. The
-- failover-tour adds heartbeat rows on top of this in a tight loop.

INSERT INTO movies (title, released) VALUES
    ('The Network Partition', '2019-09-15'),
    ('Quorum',                 '2021-03-22'),
    ('Failover',               '2024-11-08')
ON CONFLICT DO NOTHING;

INSERT INTO users (handle) VALUES
    ('umur'),
    ('alice'),
    ('bob')
ON CONFLICT DO NOTHING;

INSERT INTO reviews (user_id, movie_id, body) VALUES
    (1, 1, 'Tense the whole way through. The ending is the WAL.'),
    (2, 2, 'Beautiful film about consensus. The Raft scene is iconic.'),
    (3, 3, 'A documentary about Patroni, basically.')
ON CONFLICT DO NOTHING;
