def cache_hit_pct(result: dict):
    d = result["deltas"]
    p = result["_prev"]
    delta_total_in = d["input"] + d["cache_read"] + d["cache_write_5m"] + d["cache_write_1h"]
    prior_cache = p.get("cache_read", 0) + p.get("cache_write_5m", 0) + p.get("cache_write_1h", 0)
    if prior_cache > 0 and delta_total_in >= 1000:
        return int(d["cache_read"] * 100 / delta_total_in)
    return None
