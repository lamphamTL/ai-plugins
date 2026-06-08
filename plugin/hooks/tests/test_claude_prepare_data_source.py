import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from hosts.claude import prepare_data_source as claude


def _usage_line(input_tokens=1, output_tokens=2, cache_read=0, cache_5m=0, cache_1h=0):
    return json.dumps({
        "message": {
            "model": "claude-sonnet-4-6",
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "cache_read_input_tokens": cache_read,
                "cache_creation": {
                    "ephemeral_5m_input_tokens": cache_5m,
                    "ephemeral_1h_input_tokens": cache_1h,
                },
            },
        },
    }) + "\n"


class ClaudePrepareDataSourceRaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.usage_dir = self.root / ".claude" / "token-usage"
        self.state_json = self.usage_dir / "state.json"
        self.compaction_dir = self.root / ".claude" / "compaction"

        self.prev_usage_dir = claude.USAGE_DIR
        self.prev_state_json = claude.STATE_JSON
        self.prev_compaction_dir = claude.COMPACTION_DIR
        claude.USAGE_DIR = self.usage_dir
        claude.STATE_JSON = self.state_json
        claude.COMPACTION_DIR = self.compaction_dir
        self.addCleanup(self._restore_paths)
        self.addCleanup(self.tmp.cleanup)

    def _restore_paths(self):
        claude.USAGE_DIR = self.prev_usage_dir
        claude.STATE_JSON = self.prev_state_json
        claude.COMPACTION_DIR = self.prev_compaction_dir

    def _stdin(self, session_id="s1", transcript=None):
        return {
            "session_id": session_id,
            "transcript_path": str(transcript or (self.root / "session.jsonl")),
            "model": {"display_name": "fallback-model"},
            "cwd": str(self.root / "project"),
        }

    def test_retries_when_first_read_matches_previous_totals(self):
        transcript = self.root / "session.jsonl"
        transcript.write_text("", encoding="utf-8")
        self.usage_dir.mkdir(parents=True)
        self.state_json.write_text(json.dumps({
            "s1": {
                "input": 10,
                "output": 20,
                "cache_write": 4,
                "cache_read": 3,
            },
        }), encoding="utf-8")

        reads = [
            (10, 20, 4, 0, 3, "old-model"),
            (13, 25, 9, 2, 8, "new-model"),
        ]
        with patch.object(claude, "_read_transcript_totals", side_effect=reads), \
             patch.object(claude.time, "sleep") as sleep:
            result = claude.prepare_data_source(self._stdin(transcript=transcript))

        self.assertEqual(sleep.call_count, 1)
        self.assertEqual(result["model"], "new-model")
        self.assertEqual(result["deltas"], {
            "input": 3,
            "output": 5,
            "cache_write_5m": 5,
            "cache_write_1h": 2,
            "cache_read": 5,
        })
        state = json.loads(self.state_json.read_text(encoding="utf-8"))
        self.assertEqual(state["s1"]["output"], 25)

    def test_retries_until_transcript_file_exists(self):
        transcript = self.root / "session.jsonl"

        def create_transcript(_delay):
            transcript.write_text(
                _usage_line(input_tokens=4, output_tokens=9, cache_read=3, cache_5m=5, cache_1h=7),
                encoding="utf-8",
            )

        with patch.object(claude.time, "sleep", side_effect=create_transcript) as sleep:
            result = claude.prepare_data_source(self._stdin(transcript=transcript))

        self.assertEqual(sleep.call_count, 1)
        self.assertEqual(result["deltas"]["input"], 4)
        self.assertEqual(result["deltas"]["output"], 9)
        self.assertEqual(result["deltas"]["cache_write_5m"], 5)
        self.assertEqual(result["deltas"]["cache_write_1h"], 7)
        self.assertEqual(result["deltas"]["cache_read"], 3)

    def test_returns_none_after_retry_budget_when_delta_stays_zero(self):
        transcript = self.root / "session.jsonl"
        transcript.write_text(_usage_line(input_tokens=1, output_tokens=2), encoding="utf-8")
        self.usage_dir.mkdir(parents=True)
        self.state_json.write_text(json.dumps({
            "s1": {
                "input": 1,
                "output": 2,
                "cache_write_5m": 0,
                "cache_write_1h": 0,
                "cache_read": 0,
            },
        }), encoding="utf-8")

        with patch.object(claude.time, "sleep") as sleep:
            result = claude.prepare_data_source(self._stdin(transcript=transcript))

        self.assertIsNone(result)
        self.assertEqual(sleep.call_count, len(claude.RETRY_DELAYS))


if __name__ == "__main__":
    unittest.main()
