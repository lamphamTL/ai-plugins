def cache_hit_pct(result: dict):
    d = result["deltas"]
    p = result["_prev"]
    delta_raw_in = d["input"] + d["cache_read"]
    if p.get("cached", 0) > 0 and delta_raw_in >= 1000:
        return int(d["cache_read"] * 100 / delta_raw_in)
    return None
