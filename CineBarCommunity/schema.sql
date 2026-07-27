CREATE TABLE IF NOT EXISTS ratings (
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    media_id INTEGER NOT NULL,
    device_hash TEXT NOT NULL,
    score REAL NOT NULL CHECK (
        score >= 0 AND score <= 10 AND score * 2 = CAST(score * 2 AS INTEGER)
    ),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(media_type, media_id, device_hash)
);

CREATE INDEX IF NOT EXISTS idx_ratings_media
ON ratings(media_type, media_id, updated_at DESC);
