import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from hosts.codex.compute_spend import compute_spend


CREDIT_TO_USD = 0.04
EXPECTED_RATES = {
    "gpt-5.6-sol":   {"ri": 125.0, "ro": 750.0,  "rc": 12.50},
    "gpt-5.6-terra": {"ri": 62.50, "ro": 375.0,  "rc": 6.25},
    "gpt-5.6-luna":  {"ri": 25.0,  "ro": 150.0,  "rc": 2.50},
    "gpt-5.5":       {"ri": 125.0, "ro": 750.0,  "rc": 12.50},
    "gpt-5.5-cyber": {"ri": 500.0, "ro": 3000.0, "rc": 50.0},
    "gpt-5.4":       {"ri": 62.50, "ro": 375.0,  "rc": 6.25},
    "gpt-5.4-mini":  {"ri": 18.75, "ro": 113.0,  "rc": 1.875},
    "gpt-5.3-codex": {"ri": 43.75, "ro": 350.0,  "rc": 4.375},
    "gpt-5.2":       {"ri": 43.75, "ro": 350.0,  "rc": 4.375},
}


class CodexComputeSpendTests(unittest.TestCase):
    def test_uses_pricing_for_all_gpt_models(self):
        cases = [
            ("input", "ri", {"input": 1_000_000, "output": 0, "cache_read": 0, "reasoning": 0}),
            ("output", "ro", {"input": 0, "output": 1_000_000, "cache_read": 0, "reasoning": 0}),
            ("cache", "rc", {"input": 0, "output": 0, "cache_read": 1_000_000, "reasoning": 0}),
            ("reasoning", "ro", {"input": 0, "output": 0, "cache_read": 0, "reasoning": 1_000_000}),
        ]

        for model, rates in EXPECTED_RATES.items():
            for bucket_name, rate_key, deltas in cases:
                with self.subTest(model=model, bucket=bucket_name):
                    expected_credits = rates[rate_key]
                    expected_cost = round(expected_credits * CREDIT_TO_USD, 6)

                    spend = compute_spend(model, deltas)

                    self.assertEqual(spend, {
                        "credits": expected_credits,
                        "cost_usd": expected_cost,
                    })


if __name__ == "__main__":
    unittest.main()
