import { sqliteTable, integer, text } from "drizzle-orm/sqlite-core";

/** One row per page view. IP is stored as a one-way SHA-256 hash so raw
 *  visitor addresses are never persisted. */
export const pageVisits = sqliteTable("page_visits", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  /** Unix epoch seconds when the request arrived. */
  ts: integer("ts").notNull(),
  /** Request path, e.g. "/" or "/en". */
  path: text("path").notNull(),
  /** Cloudflare cf-ipcountry, e.g. "CN", "US". */
  country: text("country").notNull().default("--"),
  /** SHA-256 hex of the raw client IP; cannot be reversed. */
  ipHash: text("ip_hash").notNull(),
  /** Locale from the page path, e.g. "zh-Hans". */
  locale: text("locale").notNull().default("zh-Hans"),
});

export type PageVisit = typeof pageVisits.$inferSelect;
export type NewPageVisit = typeof pageVisits.$inferInsert;
