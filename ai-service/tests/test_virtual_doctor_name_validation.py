"""
Virtual Doctor name validation (Batch 2) — behavior tests.

Reported real-world failure: the patient's transcript "سوف ندخل في اسمي"
("we will enter my name" — clearly not a name) was stored as the patient's
name, and the interview carried on with "تمام يا سوف ندخل في اسمي، كم عمرك؟".

Root cause pinned by this file's first test group: the old
_is_suspicious_name compared only the WHOLE string against a small fixed
list, so any transcribed sentence not literally in that list passed. The
checks are now token-level and structural.

Two failure modes are distinguished on purpose (see _looks_like_garbled_name):
  * a single odd word ("درج") is plausibly a real name misheard -> echoed
    back for a yes/no confirmation (pre-existing behaviour, unchanged);
  * a whole sentence ("سوف ندخل في اسمي") is not -> a plain "say your first
    name again" prompt, with NO pending_confirmation, because the patient's
    next turn will be a name and not a yes/no.

No real DB, Ollama, STT, TTS, or network access anywhere in this file.
"""

import contextlib
import json
import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor import interview_engine, planner


def _fake_session(session_id="public-id", phase="intake", profile=None, language="ar"):
    return {
        "id": "row-id", "session_id": session_id, "language": language,
        "phase": phase, "chief_complaint": None,
        "patient_profile": json.dumps(profile or {}),
        "urgency_level": None,
        "recommended_specialty_id": None, "differential": None,
    }


async def _run_turn(message, fake_session, planner_result=None):
    fake_pool = AsyncMock()
    fake_pool.fetchrow = AsyncMock(return_value=fake_session)
    fake_pool.execute = AsyncMock()

    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(
            interview_engine, "get_pool", new=AsyncMock(return_value=fake_pool)))
        stack.enter_context(patch.object(
            interview_engine, "_build_turn_context", new=AsyncMock(return_value={
                "history": [], "chunks": [], "context_block": "",
                "memory_ms": 0.0, "rag_ms": 0.0})))
        stack.enter_context(patch.object(
            interview_engine, "_run_planner", new=AsyncMock(return_value=planner_result)))
        stack.enter_context(patch.object(
            interview_engine.memory, "doctor_turns", new=AsyncMock(return_value=[])))
        result = await interview_engine.handle_message(fake_session["session_id"], message)

    update = [c for c in fake_pool.execute.call_args_list
              if "UPDATE virtual_doctor_sessions" in c.args[0]][0]
    next_session = dict(fake_session)
    next_session["phase"] = update.args[2]
    next_session["patient_profile"] = update.args[4]
    return result, next_session



class TestTranscribedSentenceIsNotStoredAsName(unittest.IsolatedAsyncioTestCase):
    async def test_reported_sentence_asks_to_repeat_and_stores_nothing(self):
        fake_session = _fake_session(phase="intake")

        result, next_session = await _run_turn("سوف ندخل في اسمي", fake_session)

        profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("name", profile)
        self.assertIn("أخبرني باسمك الأول", result["reply"])
        self.assertNotIn("سوف ندخل", result["reply"])
        self.assertNotIn("pending_confirmation", profile)

    def test_unit_suspicious_name_flags_sentences_and_medical_text(self):
        for bad in ("سوف ندخل في اسمي", "عندي صداع", "أي رقم", "اسمي غلط",
                    "علي داود محمد سالم", "أنا عمري 25"):
            with self.subTest(bad=bad):
                self.assertTrue(
                    interview_engine._is_suspicious_name(interview_engine._extract_name(bad)))



class TestGreetingAndGenericNounsAreNotStoredAsName(unittest.IsolatedAsyncioTestCase):
    """Follow-up fix: after the sentence-detection fix above shipped, single-
    word STT noise that isn't a sentence — a greeting or a generic noun —
    still slipped through, because it was never a transcribed SENTENCE and
    wasn't in the (narrower, pre-follow-up) blocklist. Confirmed live: "مرحبا"
    and "كتب" were both stored as the patient's name in production sessions
    created after the sentence-detection fix."""

    async def test_greeting_word_is_not_stored_as_name(self):
        result, next_session = await _run_turn("مرحبا", _fake_session(phase="intake"))

        profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("name", profile)
        self.assertNotIn("شكرًا يا مرحبا", result["reply"])

    async def test_generic_noun_is_not_stored_as_name(self):
        result, next_session = await _run_turn("كتب", _fake_session(phase="intake"))

        profile = json.loads(next_session["patient_profile"])
        self.assertNotIn("name", profile)
        self.assertNotIn("شكرًا يا كتب", result["reply"])

    def test_unit_new_blocklist_entries_are_flagged(self):
        for bad in ("مرحبا", "أهلا", "اهلًا", "السلام", "كتب", "كتاب", "كلمة"):
            with self.subTest(bad=bad):
                self.assertTrue(
                    interview_engine._is_suspicious_name(interview_engine._extract_name(bad)))



class TestRealNamesAreAccepted(unittest.IsolatedAsyncioTestCase):
    async def test_simple_name_is_stored_and_interview_continues(self):
        fake_session = _fake_session(phase="intake")
        plan = planner.PlannerResult(
            reply="شكرًا يا علي. كم عمرك؟", phase="intake",
            profile_updates={"name": "علي"}, source="intake",
        )

        _, next_session = await _run_turn("علي", fake_session, plan)

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile.get("name"), "علي")
        self.assertNotIn("pending_confirmation", profile)

    async def test_omar_is_stored_normally_despite_meaning_age(self):
        """"عمر" is both a common male name AND the word for "age" — the
        blocklist added in the follow-up batch deliberately excludes bare
        "عمر" (only "عمري"/"العمر", the possessive/definite age forms, are
        blocked) so a patient actually named Omar is never refused."""
        fake_session = _fake_session(phase="intake")
        plan = planner.PlannerResult(
            reply="شكرًا يا عمر. كم عمرك؟", phase="intake",
            profile_updates={"name": "عمر"}, source="intake",
        )

        _, next_session = await _run_turn("عمر", fake_session, plan)

        profile = json.loads(next_session["patient_profile"])
        self.assertEqual(profile.get("name"), "عمر")
        self.assertNotIn("pending_confirmation", profile)

    def test_unit_common_arabic_names_are_not_flagged(self):
        """Regression guard for the collision class this batch actually hit:
        normalize_text folds alef-maqsura to ya, so the preposition "على"
        collapses onto the name "علي". Blocking a real, extremely common
        name is worse than missing a garbled one."""
        for good in ("علي", "علي داود", "محمد", "سارة", "أحمد", "عمر",
                     "ليلى", "أمل", "حسام", "نور", "عبد الله", "علي داود محمد"):
            with self.subTest(good=good):
                self.assertFalse(
                    interview_engine._is_suspicious_name(interview_engine._extract_name(good)))



class TestBorderlineNameStillEchoesForConfirmation(unittest.IsolatedAsyncioTestCase):
    async def test_single_odd_word_is_echoed_with_yes_no_confirmation(self):
        fake_session = _fake_session(phase="intake")

        result, next_session = await _run_turn("درج", fake_session)

        profile = json.loads(next_session["patient_profile"])
        self.assertIn("درج", result["reply"])
        self.assertIn("هل هذا اسمك", result["reply"])
        self.assertEqual(profile["pending_confirmation"]["field"], "name")



class TestNameRepeatDoesNotLoopForever(unittest.IsolatedAsyncioTestCase):
    async def test_gives_up_after_cap_and_marks_the_name_unconfirmed(self):
        session = _fake_session(phase="intake")

        for _ in range(interview_engine.MAX_NAME_REPEAT_ATTEMPTS):
            result, session = await _run_turn("سوف ندخل في اسمي", session)
            self.assertIn("أخبرني باسمك الأول", result["reply"])

        result, session = await _run_turn("سوف ندخل في اسمي", session)
        profile = json.loads(session["patient_profile"])

        self.assertIn("كم عمرك", result["reply"])
        self.assertFalse(profile["confirmed_fields"]["name"])
        self.assertIn("name", profile["uncertain_fields"])



class TestAgePhaseHandlesNonNumericAnswer(unittest.IsolatedAsyncioTestCase):
    async def test_non_numeric_age_reasks_without_crashing(self):
        fake_session = _fake_session(phase="intake", profile={"name": "علي"})
        plan = planner.PlannerResult(
            reply=interview_engine.ASK_AGE_RETRY["ar"], phase="intake", source="intake",
        )

        result, next_session = await _run_turn("أي رقم", fake_session, plan)

        profile = json.loads(next_session["patient_profile"])
        self.assertIsNone(profile.get("age"))
        self.assertIn("كم عمرك", result["reply"])


if __name__ == "__main__":
    unittest.main()
