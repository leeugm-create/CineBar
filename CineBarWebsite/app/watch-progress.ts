/**
 * 本地观看进度（对标 zip0 的 lumina:watch-history）：
 * 播放中的影片把进度存 localStorage，首页「接着上次看」读取并续播。
 * 纯本地存储，不注册、不上传。
 */

export type WatchProgress = {
  /** 唯一键：`movie:<title>:<year>` 或 `tv:<title>:<year>`。 */
  key: string;
  type: "movie" | "tv";
  title: string;
  year: string;
  poster: string | null;
  /** 播放源的线路标签（如 "量子"、"Moovie"）。 */
  sourceLabel: string;
  currentTime: number;
  duration: number;
  updatedAt: number;
};

const KEY = "cinebar.watch.progress";
const MAX_ITEMS = 12;
/** 少于 10 秒的观看不记录（误点不算）。 */
const MIN_SECONDS = 10;
/** 距片尾不足 20 秒视为看完，清掉记录。 */
const END_THRESHOLD = 20;

function load(): WatchProgress[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((x): x is WatchProgress => x && typeof x === "object" && typeof x.key === "string")
      .slice(0, MAX_ITEMS);
  } catch {
    return [];
  }
}

function save(items: WatchProgress[]): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(items.slice(0, MAX_ITEMS)));
  } catch {
    // private mode or quota exceeded: ignore
  }
}

/** 按更新时间倒序的全部进度（首页「接着上次看」用）。 */
export function listProgress(): WatchProgress[] {
  return load().sort((a, b) => b.updatedAt - a.updatedAt);
}

/** 更新一条进度：同 key 覆盖并置顶，总量封顶。 */
export function recordProgress(p: WatchProgress): void {
  if (typeof window === "undefined") return;
  if (!Number.isFinite(p.duration) || p.duration <= 0) return;
  // 距片尾不足 20 秒视为看完，清掉该条。
  if (p.duration - p.currentTime < END_THRESHOLD) {
    removeProgress(p.key);
    return;
  }
  const items = load().filter((x) => x.key !== p.key);
  save([p, ...items]);
}

/** 删除一条进度（看完或手动清除）。 */
export function removeProgress(key: string): void {
  if (typeof window === "undefined") return;
  save(load().filter((x) => x.key !== key));
}

/** 清空全部进度。 */
export function clearProgress(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}

/** 供 inline-player 节流：距上次写入超过 5 秒才落盘。 */
export function shouldWriteProgress(lastWriteAt: number, now: number): boolean {
  return now - lastWriteAt >= 5000;
}

export { MIN_SECONDS };
