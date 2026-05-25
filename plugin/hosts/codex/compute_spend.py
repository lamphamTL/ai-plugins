from ._constants import CREDIT_TO_USD, DEFAULT_RATE, RATES


def compute_spend(model: str, deltas: dict):
    r = RATES.get(model.lower(), DEFAULT_RATE)
    credits = round(
        (deltas["input"] * r["ri"]
         + (deltas["output"] + deltas["reasoning"]) * r["ro"]
         + deltas["cache_read"] * r["rc"]) / 1_000_000,
        6,
    )
    cost = round(credits * CREDIT_TO_USD, 6)
    return {"credits": credits, "cost_usd": cost}
