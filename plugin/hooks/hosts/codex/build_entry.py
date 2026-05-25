from datetime import datetime, timezone


def build_entry(result: dict, spend: dict) -> dict:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "ts":         ts,
        "session_id": result["session_id"],
        "model":      result["model"],
        "project":    result["project"],
        "isSubAgent": False,
        "tokens":     result["deltas"],
        "credits":    spend["credits"],
        "cost_usd":   spend["cost_usd"],
    }
