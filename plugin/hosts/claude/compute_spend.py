def compute_spend(model: str, deltas: dict):
    cost = round(
        (deltas["input"] * 3
         + deltas["output"] * 15
         + deltas["cache_write"] * 3.75
         + deltas["cache_read"] * 0.30) / 1_000_000,
        6,
    )
    return {"cost_usd": cost}
