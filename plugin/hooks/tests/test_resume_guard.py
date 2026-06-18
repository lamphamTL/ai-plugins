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


class ResumeGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def _transcript(self, *lines):
        path = self.root / "session.jsonl"
        path.write_text("".join(lines), encoding="utf-8")
        return path

    def test_parses_latest_timestamp_from_claude_rows(self):
        transcript = self._transcript(
            json.dumps({"timestamp": "2026-06-18T08:00:00Z", "message": {}}) + "\n",
            "not-json\n",
            json.dumps({"timestamp": "bad-time"}) + "\n",
            json.dumps({"timestamp": "2026-06-18T08:12:30+00:00"}) + "\n",
        )

        result = resume_guard.latest_transcript_timestamp(str(transcript))

        self.assertEqual(result, datetime(2026, 6, 18, 8, 12, 30, tzinfo=timezone.utc))

    def test_parses_latest_timestamp_from_codex_rows(self):
        transcript = self._transcript(
            json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "agent_reasoning",
                    "timestamp": "2026-06-18T09:00:00.123456789Z",
                },
            }) + "\n",
            json.dumps({
                "type": "event_msg",
                "payload": {
                    "type": "user_message",
                    "time": "2026-06-18T09:05:00Z",
                },
            }) + "\n",
        )

        result = resume_guard.latest_transcript_timestamp(str(transcript))

        self.assertEqual(result, datetime(2026, 6, 18, 9, 5, tzinfo=timezone.utc))

    def test_timestamp_less_empty_and_missing_transcripts_return_none(self):
        timestamp_less = self._transcript(
            json.dumps({"message": {"content": "hello"}}) + "\n",
            "\n",
        )

        self.assertIsNone(resume_guard.latest_transcript_timestamp(str(timestamp_less)))
        self.assertIsNone(resume_guard.latest_transcript_timestamp(str(self.root / "missing.jsonl")))
        self.assertIsNone(resume_guard.latest_transcript_timestamp(None))

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
        transcript = self._transcript(json.dumps({"timestamp": "2026-06-18T09:50:00Z"}) + "\n")
        code, output = resume_guard.run(
            "claude",
            json.dumps({"transcript_path": str(transcript)}),
            now=datetime(2026, 6, 18, 10, 0, tzinfo=timezone.utc),
        )

        self.assertEqual(code, 0)
        self.assertEqual(output, "")

    def test_run_blocks_stale_session_when_dialog_cancels(self):
        transcript = self._transcript(json.dumps({"timestamp": "2026-06-18T08:00:00Z"}) + "\n")

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


if __name__ == "__main__":
    unittest.main()
