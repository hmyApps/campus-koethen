import { TtlCache } from './ttl-cache';

describe('TtlCache', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('serves a fresh entry from cache without calling the factory again', async () => {
    const factory = jest.fn().mockResolvedValue('value');
    const cache = new TtlCache<string>(60_000);

    await expect(cache.getOrSet('key', factory)).resolves.toBe('value');
    await expect(cache.getOrSet('key', factory)).resolves.toBe('value');

    expect(factory).toHaveBeenCalledTimes(1);
  });

  it('refetches once the entry has expired', async () => {
    const factory = jest.fn().mockResolvedValueOnce('first').mockResolvedValueOnce('second');
    const cache = new TtlCache<string>(1_000);

    await expect(cache.getOrSet('key', factory)).resolves.toBe('first');
    jest.advanceTimersByTime(1_001);
    await expect(cache.getOrSet('key', factory)).resolves.toBe('second');

    expect(factory).toHaveBeenCalledTimes(2);
  });

  it('keeps separate entries per key', async () => {
    const factory = jest.fn().mockResolvedValueOnce('de').mockResolvedValueOnce('en');
    const cache = new TtlCache<string>(60_000);

    await expect(cache.getOrSet('de', factory)).resolves.toBe('de');
    await expect(cache.getOrSet('en', factory)).resolves.toBe('en');

    expect(factory).toHaveBeenCalledTimes(2);
  });

  it('does not cache a rejected factory call, so the next call retries', async () => {
    const factory = jest
      .fn()
      .mockRejectedValueOnce(new Error('upstream unavailable'))
      .mockResolvedValueOnce('value');
    const cache = new TtlCache<string>(60_000);

    await expect(cache.getOrSet('key', factory)).rejects.toThrow('upstream unavailable');
    await expect(cache.getOrSet('key', factory)).resolves.toBe('value');

    expect(factory).toHaveBeenCalledTimes(2);
  });

  it('never answers with an expired entry, not even when the refresh fails', async () => {
    // Deliberately no stale-on-error: a stale answer would carry no staleness
    // marker, and a post list filtered by its validity window at request time
    // would keep showing a post past its `validUntil` for as long as the CMS
    // is down. The class comment once promised otherwise; this pins the truth.
    const factory = jest
      .fn()
      .mockResolvedValueOnce('first')
      .mockRejectedValueOnce(new Error('upstream unavailable'));
    const cache = new TtlCache<string>(1_000);

    await expect(cache.getOrSet('key', factory)).resolves.toBe('first');
    jest.advanceTimersByTime(1_001);

    await expect(cache.getOrSet('key', factory)).rejects.toThrow('upstream unavailable');
    expect(cache.size).toBe(0);
  });

  it('does not grow without bound when the keys keep changing', async () => {
    // The rooms endpoint takes its cache key from validated query parameters,
    // so an unauthenticated caller decides how many DISTINCT keys exist. An
    // unbounded map would let that caller decide how much memory this process
    // holds for good.
    const cache = new TtlCache<string>(60_000, 8);

    for (let i = 0; i < 500; i += 1) {
      await cache.getOrSet(`key-${i}`, async () => `value-${i}`);
    }

    expect(cache.size).toBeLessThanOrEqual(8);
  });

  it('drops an expired entry instead of keeping it until the same key returns', async () => {
    const cache = new TtlCache<string>(1_000, 8);

    await cache.getOrSet('stale', async () => 'value');
    expect(cache.size).toBe(1);

    jest.advanceTimersByTime(1_001);
    await cache.getOrSet('other', async () => 'value');

    // "other" is the only live entry; "stale" must not linger.
    expect(cache.size).toBe(1);
  });

  it('evicts the least recently used entry once the capacity is reached', async () => {
    const factory = jest.fn(async () => 'value');
    const cache = new TtlCache<string>(60_000, 2);

    await cache.getOrSet('a', factory);
    await cache.getOrSet('b', factory);
    // Touching "a" makes "b" the least recently used one.
    await cache.getOrSet('a', factory);
    await cache.getOrSet('c', factory);

    expect(factory).toHaveBeenCalledTimes(3);

    // "a" survived, "b" was evicted.
    await cache.getOrSet('a', factory);
    expect(factory).toHaveBeenCalledTimes(3);
    await cache.getOrSet('b', factory);
    expect(factory).toHaveBeenCalledTimes(4);
  });

  it('shares one in-flight request across concurrent misses for the same key', async () => {
    const factory = jest.fn().mockResolvedValue('value');
    const cache = new TtlCache<string>(60_000);

    const [first, second] = await Promise.all([
      cache.getOrSet('key', factory),
      cache.getOrSet('key', factory),
    ]);

    expect(first).toBe('value');
    expect(second).toBe('value');
    expect(factory).toHaveBeenCalledTimes(1);
  });
});
