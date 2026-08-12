-- CineAI 代理 D1 schema
-- 用法：wrangler d1 execute cineai-proxy --remote --file=./schema.sql

-- 设备匿名 ID 每日用量（次数 + token 双限制）
CREATE TABLE IF NOT EXISTS usage (
  device TEXT NOT NULL,
  day    TEXT NOT NULL,
  calls  INTEGER NOT NULL DEFAULT 0,
  tokens INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device, day)
);

-- 精确缓存（第一层）：消息规范化哈希 → 结果
CREATE TABLE IF NOT EXISTS rsp_cache (
  hash       TEXT PRIMARY KEY,
  body       TEXT NOT NULL,
  at         INTEGER NOT NULL
);
