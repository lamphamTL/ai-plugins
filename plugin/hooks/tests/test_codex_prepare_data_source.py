import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from hosts.codex import prepare_data_source as codex_prepare


SESSION_ID = "session-123"


def _token_count_line(input_tokens, output_tokens, cached_input_tokens=0, reasoning_output_tokens=0):
    return json.dumps({
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "cached_input_tokens": cached_input_tokens,
                    "reasoning_output_tokens": reasoning_output_tokens,
                },
            },
        },
    }) + "\n"


class CodexPrepareDataSourceRetryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.usage_dir = self.root / "token-usage"
        self.state_json = self.usage_dir / "state.json"

        self.usage_dir_patch = mock.patch.object(codex_prepare, "USAGE_DIR", self.usage_dir)
        self.state_json_patch = mock.patch.object(codex_prepare, "STATE_JSON", self.state_json)
        self.usage_dir_patch.start()
        self.state_json_patch.start()
        self.addCleanup(self.usage_dir_patch.stop)
        self.addCleanup(self.state_json_patch.stop)

    def _stdin(self, transcript):
        return {
            "session_id": SESSION_ID,
            "transcript_path": str(transcript),
            "model": "gpt-5.5",
            "cwd": str(self.root / "repo"),
        }

    def test_retries_until_provided_transcript_exists(self):
        transcript = self.root / "session.jsonl"
        sleep_calls = []

        def fake_sleep(delay):
            sleep_calls.append(delay)
            transcript.write_text(_token_count_line(10, 5, 2, 1), encoding="utf-8")

        with mock.patch.object(codex_prepare, "_find_transcript", return_value=None), \
             mock.patch.object(codex_prepare.time, "sleep", side_effect=fake_sleep):
            result = codex_prepare.prepare_data_source(self._stdin(transcript))

        self.assertEqual(sleep_calls, [0.1])
        self.assertEqual(result["deltas"], {
            "input": 8,
            "output": 5,
            "cache_read": 2,
            "reasoning": 1,
        })

    def test_retries_until_token_count_is_flushed(self):
        transcript = self.root / "session.jsonl"
        transcript.write_text(json.dumps({"type": "event_msg", "payload": {"type": "other"}}) + "\n", encoding="utf-8")
        sleep_calls = []

        def fake_sleep(delay):
            sleep_calls.append(delay)
            transcript.write_text(transcript.read_text(encoding="utf-8") + _token_count_line(12, 7, 3, 2), encoding="utf-8")

        with mock.patch.object(codex_prepare.time, "sleep", side_effect=fake_sleep):
            result = codex_prepare.prepare_data_source(self._stdin(transcript))

        self.assertEqual(sleep_calls, [0.1])
        self.assertEqual(result["deltas"], {
            "input": 9,
            "output": 7,
            "cache_read": 3,
            "reasoning": 2,
        })

    def test_retries_when_delta_is_zero(self):
        transcript = self.root / "session.jsonl"
        transcript.write_text(_token_count_line(20, 8, 5, 2), encoding="utf-8")
        self.usage_dir.mkdir(parents=True)
        self.state_json.write_text(json.dumps({
            SESSION_ID: {
                "input": 20,
                "output": 8,
                "cached": 5,
                "reasoning": 2,
            },
        }), encoding="utf-8")
        sleep_calls = []

        def fake_sleep(delay):
            sleep_calls.append(delay)
            transcript.write_text(transcript.read_text(encoding="utf-8") + _token_count_line(30, 11, 6, 3), encoding="utf-8")

        with mock.patch.object(codex_prepare.time, "sleep", side_effect=fake_sleep):
            result = codex_prepare.prepare_data_source(self._stdin(transcript))

        self.assertEqual(sleep_calls, [0.1])
        self.assertEqual(result["deltas"], {
            "input": 9,
            "output": 3,
            "cache_read": 1,
            "reasoning": 1,
        })
        self.assertEqual(json.loads(self.state_json.read_text(encoding="utf-8"))[SESSION_ID], {
            "input": 30,
            "output": 11,
            "cached": 6,
            "reasoning": 3,
        })

    def test_missing_transcript_returns_none_after_bounded_retries(self):
        transcript = self.root / "missing.jsonl"
        sleep_calls = []

        def fake_sleep(delay):
            sleep_calls.append(delay)

        with mock.patch.object(codex_prepare, "_find_transcript", return_value=None), \
             mock.patch.object(codex_prepare.time, "sleep", side_effect=fake_sleep):
            result = codex_prepare.prepare_data_source(self._stdin(transcript))

        self.assertIsNone(result)
        self.assertEqual(sleep_calls, [0.1, 0.15, 0.2, 0.25])


if __name__ == "__main__":
    unittest.main()
