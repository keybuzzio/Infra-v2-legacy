INSERT INTO schema_migrations (version) VALUES ('20231211010807') ON CONFLICT (version) DO NOTHING;
SELECT version FROM schema_migrations WHERE version = '20231211010807';

