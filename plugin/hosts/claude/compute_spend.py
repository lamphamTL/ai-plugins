from .model_pricing import DEFAULT_RATE, RATES


def _lookup_rate(model: str):
    m = (model or "").lower()
    best_key = ""
    for key in RATES:
        if m.startswith(key) and len(key) > len(best_key):
            best_key = key
    return RATES[best_key] if best_key else DEFAULT_RATE


def compute_spend(model: str, deltas: dict):
    r = _lookup_rate(model)
    cost = round(
        (deltas["input"] * r["ri"]
         + deltas["output"] * r["ro"]
         + deltas["cache_write"] * r["rw"]
         + deltas["cache_read"] * r["rc"]) / 1_000_000,
        6,
    )
    return {"cost_usd": cost}
