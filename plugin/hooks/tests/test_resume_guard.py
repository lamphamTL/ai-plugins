import importlib.util
import json
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "resume-guard.py"
SPEC = importlib.util.spec_from_file_location("resume_guard", SCRIPT_PATH)
resume_guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resume_guard)


def _token_count_line(timestamp=None, *, payload_timestamp=None, cached_input_tokens=0):
    row = {
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": 10,
                    "output_tokens": 2,
                    "cached_input_tokens": cached_input_tokens,
                },
            },
        },
    }
    if timestamp is not None:
        row["timestamp"] = timestamp
    if payload_timestamp is not None:
        row["payload"]["timestamp"] = payload_timestamp
    return json.dumps(row) + "\n"


class ResumeGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def _transcript(self, *lines):
        path = self.root / "session.jsonl"
        path.write_text("".join(lines), encoding="utf-8")
        return path

    def test_parses_latest_token_count_timestamp_and_ignores_malformed_jsonl(self):
        transcript = self._transcript(
            _token_count_line("2026-06-18T08:00:00Z"),
            "not-json\n",
            _token_count_line("bad-time"),
            json.dumps({
                "type": "event_msg",
                "timestamp": "2026-06-18T09:00:00Z",
                "payload": {"type": "user_message"},
            }) + "\n",
            _token_count_line("2026-06-18T08:12:30+00:00"),
        )

        result = resume_guard.latest_token_count_timestamp(str(transcript))

        self.assertEqual(result, datetime(2026, 6, 18, 8, 12, 30, tzinfo=timezone.utc))

    def test_parses_token_count_payload_timestamp(self):
        transcript = self._transcript(
            json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "timestamp": "2026-06-18T09:00:00.123456789Z",
                },
            }) + "\n",
        )

        result = resume_guard.latest_token_count_timestamp(str(transcript))

        self.assertEqual(
            result,
            datetime(2026, 6, 18, 9, 0, 0, 123456, tzinfo=timezone.utc),
        )

    def test_empty_missing_and_no_token_count_transcripts_return_none(self):
        no_token_count = self._transcript(
            json.dumps({"message": {"content": "hello"}}) + "\n",
            json.dumps({
                "type": "event_msg",
                "timestamp": "2026-06-18T09:00:00Z",
                "payload": {"type": "agent_reasoning"},
            }) + "\n",
            "\n",
        )
        empty = self.root / "empty.jsonl"
        empty.write_text("", encoding="utf-8")

        self.assertIsNone(resume_guard.latest_token_count_timestamp(str(no_token_count)))
        self.assertIsNone(resume_guard.latest_token_count_timestamp(str(empty)))
        self.assertIsNone(resume_guard.latest_token_count_timestamp(str(self.root / "missing.jsonl")))
        self.assertIsNone(resume_guard.latest_token_count_timestamp(None))

    def test_stale_active_and_missing_decisions(self):
        now = datetime(2026, 6, 18, 10, 0, tzinfo=timezone.utc)

        self.assertFalse(resume_guard.is_stale_session(None, now=now))
        self.assertFalse(resume_guard.is_stale_session(now - timedelta(minutes=55), now=now))
        self.assertTrue(resume_guard.is_stale_session(now - timedelta(minutes=56), now=now))
        self.assertFalse(resume_guard.is_stale_session(now + timedelta(minutes=1), now=now))

    def test_dialog_continue_allows(self):
        calls = []

        def runner(*args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args[0], 0, stdout="button returned:Continue\n", stderr="")

        self.assertTrue(resume_guard.confirm_stale_resume(runner))
        script = calls[0][0][0][2]
        self.assertIn(resume_guard.DIALOG_MESSAGE, script)
        self.assertIn('buttons {"Cancel", "Continue"}', script)
        self.assertIn('default button "Cancel"', script)

    def test_dialog_cancel_and_failure_block(self):
        def cancel_runner(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 1, stdout="", stderr="User canceled.")

        def failure_runner(*args, **kwargs):
            raise OSError("osascript missing")

        self.assertFalse(resume_guard.confirm_stale_resume(cancel_runner))
        self.assertFalse(resume_guard.confirm_stale_resume(failure_runner))

    def test_host_block_response_keys(self):
        self.assertEqual(
            set(resume_guard.block_response("claude").keys()),
            {"decision", "reason"},
        )
        self.assertEqual(
            set(resume_guard.block_response("codex").keys()),
            {"continue", "systemMessage"},
        )

    def test_run_allows_active_session_without_output(self):
        transcript = self._transcript(_token_count_line("2026-06-18T09:50:00Z"))
        code, output = resume_guard.run(
            "claude",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, tzinfo=timezone.utc),
        )

        self.assertEqual(code, 0)
        self.assertEqual(output, "")

    def test_run_blocks_stale_session_when_dialog_cancels(self):
        transcript = self._transcript(_token_count_line("2026-06-18T08:00:00Z"))

        def cancel_runner(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 1, stdout="", stderr="")

        code, output = resume_guard.run(
            "codex",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, tzinfo=timezone.utc),
            dialog_runner=cancel_runner,
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output), resume_guard.block_response("codex"))

    def test_run_allows_stale_session_when_dialog_continues(self):
        transcript = self._transcript(_token_count_line("2026-06-18T08:00:00Z"))

        def continue_runner(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, stdout="button returned:Continue\n", stderr="")

        code, output = resume_guard.run(
            "codex",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, tzinfo=timezone.utc),
            dialog_runner=continue_runner,
        )

        self.assertEqual(code, 0)
        self.assertEqual(output, "")

    def test_run_allows_recent_token_count_and_ignores_cache_hit_percentage(self):
        transcript = self._transcript(_token_count_line("2026-06-18T09:05:00Z", cached_input_tokens=0))
        calls = []

        def runner(*args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args[0], 1, stdout="", stderr="")

        code, output = resume_guard.run(
            "codex",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, 0, tzinfo=timezone.utc),
            dialog_runner=runner,
        )

        self.assertEqual(code, 0)
        self.assertEqual(output, "")
        self.assertEqual(calls, [])

    def test_run_allows_missing_empty_and_no_token_count_transcripts(self):
        empty = self.root / "empty.jsonl"
        empty.write_text("", encoding="utf-8")
        no_token_count = self._transcript(
            json.dumps({
                "type": "event_msg",
                "timestamp": "2026-06-18T08:00:00Z",
                "payload": {"type": "user_message"},
            }) + "\n",
        )

        for transcript in (self.root / "missing.jsonl", empty, no_token_count):
            with self.subTest(transcript=transcript):
                code, output = resume_guard.run(
                    "codex",
                    json.dumps({"transcript_path": str(transcript)}),
                    now=datetime(2026, 6, 18, 10, 0, 1, tzinfo=timezone.utc),
                )

                self.assertEqual(code, 0)
                self.assertEqual(output, "")

    def test_run_allows_prompt_only_transcript(self):
        transcript = self._transcript(json.dumps({
            "type": "event_msg",
            "timestamp": "2026-06-18T10:00:00Z",
            "payload": {"type": "user_message"},
        }) + "\n")
        code, output = resume_guard.run(
            "codex",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, 1, tzinfo=timezone.utc),
        )

        self.assertEqual(code, 0)
        self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
