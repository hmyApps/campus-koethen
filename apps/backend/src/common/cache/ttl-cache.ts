/**
 * Small in-memory read-through cache for rarely-changing, editorially-owned
 * reads (Strapi collections). Single-instance only — no distributed
 * invalidation, which is fine given the process topology here.
 *
 * A failed `factory()` call is never cached: the error propagates to the
 * caller exactly as an uncached call would, and the next call tries again.
 *
 * There is deliberately NO stale-on-error. A refresh only happens once an
 * entry has expired, and an expired entry is gone before the refresh starts,
 * so a failing upstream is answered with its error, not with old data. Serving
 * stale data here would carry no staleness marker to the client, and the post
 * lists cached through this class are filtered by a validity window evaluated
 * at request time — an outage would keep a withdrawn post visible.
 *
 * "Small" is enforced, not assumed. A cache key is often derived from request
 * input, and an unbounded map would let whoever sends those requests decide how
 * much memory this process holds for good — expired entries would sit there
 * until the very same key came back, which for a one-off key is never. So the
 * map has a hard capacity: expired entries go first, then the least recently
 * used one.
 */

/** Plenty for every catalogue this API caches, far too little to hurt. */
export const DEFAULT_MAX_ENTRIES = 64;

export class TtlCache<V> {
  /**
   * Insertion order doubles as recency order: a hit re-inserts its key, so the
   * first key a `Map` iterator yields is always the least recently used one.
   */
  private readonly entries = new Map<string, { value: V; expiresAt: number }>();
  private readonly pending = new Map<string, Promise<V>>();

  constructor(
    private readonly ttlMs: number,
    private readonly maxEntries: number = DEFAULT_MAX_ENTRIES,
  ) {}

  /** How many entries are currently held. Exposed so the bound is testable. */
  get size(): number {
    return this.entries.size;
  }

  async getOrSet(key: string, factory: () => Promise<V>): Promise<V> {
    const cached = this.entries.get(key);
    if (cached) {
      if (cached.expiresAt > Date.now()) {
        // Re-insert so this key becomes the most recently used one.
        this.entries.delete(key);
        this.entries.set(key, cached);
        return cached.value;
      }
      this.entries.delete(key);
    }

    // Concurrent misses for the same key share one in-flight request instead
    // of each firing their own upstream call.
    const inFlight = this.pending.get(key);
    if (inFlight) {
      return inFlight;
    }

    const request = factory()
      .then((value) => {
        this.store(key, value);
        return value;
      })
      .finally(() => {
        this.pending.delete(key);
      });

    this.pending.set(key, request);
    return request;
  }

  private store(key: string, value: V): void {
    const now = Date.now();
    this.entries.delete(key);

    // Expired entries are dropped eagerly rather than on their next hit: a key
    // derived from request input may never be asked for again, and waiting for
    // that hit means holding it for the lifetime of the process.
    for (const [candidate, entry] of this.entries) {
      if (entry.expiresAt <= now) this.entries.delete(candidate);
    }

    this.entries.set(key, { value, expiresAt: now + this.ttlMs });

    // Still over capacity: evict least recently used first.
    while (this.entries.size > this.maxEntries) {
      const oldest = this.entries.keys().next();
      if (oldest.done) break;
      this.entries.delete(oldest.value);
    }
  }
}
