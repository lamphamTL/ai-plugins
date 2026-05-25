from datetime import datetime, timezone


def build_entry(result: dict, spend: dict) -> dict:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "ts":         ts,
        "session_id": result["session_id"],
        "model":      result["model"],
        "project":    result["project"],
        "tokens":     result["deltas"],
        "cost_usd":   spend["cost_usd"],
        "isSubAgent": bool(result["agent_id"]),
        "agent_type": result["agent_type"],
    }
