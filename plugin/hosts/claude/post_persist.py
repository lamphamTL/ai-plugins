import json

from .model_pricing import USAGE_DIR


def post_persist(entry: dict, result: dict) -> None:
    (USAGE_DIR / "last-turn.json").write_text(json.dumps({
        "session_id": result["session_id"],
        **result["deltas"],
        "cost_usd":   entry["cost_usd"],
    }))
