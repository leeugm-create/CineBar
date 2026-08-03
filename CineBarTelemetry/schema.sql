CREATE TABLE IF NOT EXISTS installs (
  install_hash TEXT PRIMARY KEY,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build INTEGER NOT NULL,
  platform TEXT NOT NULL,
  os_major INTEGER NOT NULL,
  architecture TEXT NOT NULL,
  language TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS installs_last_seen_at_idx
  ON installs(last_seen_at);
