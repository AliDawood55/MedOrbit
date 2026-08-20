"""
Virtual Doctor TTS Arabic text normalization — behavior tests.

Part of the "MedOrbit Virtual Doctor — Formal Arabic Voice Quality Upgrade"
batch. Pins voice/tts.py's _normalize_arabic_tts_text() (Batch 2): cleans up
punctuation/formatting NOISE before Piper synthesis without ever touching a
word, so medical terms and meaning are always preserved by construction.

Also pins the env-driven SynthesisConfig plumbing (Batch 3,
_synthesis_config_for()): a verified no-op unless an operator explicitly
sets one of the VD_TTS_AR_* env vars, since piper-tts==1.6.0's
SynthesisConfig falls back to the voice's own tuned .onnx.json defaults for
any field left None (verified by reading phoneme_ids_to_audio() directly,
not assumed).

Pure function tests only — no real Piper model load, no audio synthesis, no
network access anywhere in this file.
"""

import importlib
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from virtual_doctor.voice import tts


# ===========================================================================
# 1. Repeated punctuation is collapsed
# ===========================================================================

class TestRepeatedPunctuationIsCollapsed(unittest.TestCase):
    def test_repeated_arabic_question_marks_collapse_to_one(self):
        self.assertEqual(tts._normalize_arabic_tts_text("كيف حالك؟؟؟"), "كيف حالك؟")

    def test_repeated_exclamation_marks_become_a_period(self):
        self.assertEqual(tts._normalize_arabic_tts_text("انتبه!!!"), "انتبه.")

    def test_repeated_commas_and_periods_collapse(self):
        self.assertEqual(tts._normalize_arabic_tts_text("الاسم،، والعمر.."), "الاسم، والعمر.")


# ===========================================================================
# 2. Markdown/technical artifacts are stripped
# ===========================================================================

class TestMarkdownArtifactsAreStripped(unittest.TestCase):
    def test_bold_markers_are_removed(self):
        self.assertEqual(tts._normalize_arabic_tts_text("**مهم:** راجع الطبيب"), "مهم: راجع الطبيب")

    def test_heading_markers_are_removed(self):
        self.assertEqual(tts._normalize_arabic_tts_text("## ملخص الحالة"), "ملخص الحالة")

    def test_bullet_markers_are_removed(self):
        self.assertEqual(
            tts._normalize_arabic_tts_text("- الصداع\n- الحمى"),
            "الصداع الحمى",
        )


# ===========================================================================
# 3. Whitespace/newlines collapse into natural sentence breaks
# ===========================================================================

class TestWhitespaceCollapses(unittest.TestCase):
    def test_multiple_newlines_become_a_single_space(self):
        self.assertEqual(
            tts._normalize_arabic_tts_text("السطر الأول\n\n\nالسطر الثاني"),
            "السطر الأول السطر الثاني",
        )

    def test_repeated_spaces_collapse_to_one(self):
        self.assertEqual(tts._normalize_arabic_tts_text("مرحبًا    بك"), "مرحبًا بك")


# ===========================================================================
# 4. Medically important words and meaning are always preserved
# ===========================================================================

class TestMeaningIsPreserved(unittest.TestCase):
    def test_medical_terms_survive_untouched(self):
        text = "قد تكون هذه أعراض التهاب الزائدة الدودية، راجع الطوارئ فورًا."
        self.assertEqual(tts._normalize_arabic_tts_text(text), text)

    def test_single_question_mark_is_preserved_not_stripped(self):
        self.assertEqual(tts._normalize_arabic_tts_text("كم عمرك؟"), "كم عمرك؟")

    def test_no_diacritics_are_added(self):
        # Fatha (َ) must never appear in the output if it wasn't in the
        # input — this function only removes/collapses noise, never adds.
        text = "هل تشعر بألم في الصدر؟"
        result = tts._normalize_arabic_tts_text(text)
        self.assertNotIn("َ", result)
        self.assertEqual(result, text)

    def test_empty_and_whitespace_only_text_is_handled(self):
        self.assertEqual(tts._normalize_arabic_tts_text(""), "")
        self.assertEqual(tts._normalize_arabic_tts_text("   "), "")


# ===========================================================================
# 5. _prepare_text wires normalization in for Arabic only
# ===========================================================================

class TestPrepareTextWiresNormalizationForArabicOnly(unittest.TestCase):
    def test_arabic_text_is_normalized_by_prepare_text(self):
        prepared = tts._prepare_text("مرحبًا؟؟؟ **تمام**", "ar")
        self.assertEqual(prepared, "مرحبًا؟ تمام")

    def test_english_text_is_not_run_through_arabic_normalization(self):
        # English already goes through _prepare_text unmodified except for
        # the (irrelevant here) Latin-run transliteration pass; repeated
        # punctuation in English text must NOT be touched by this batch.
        prepared = tts._prepare_text("Really???", "en")
        self.assertEqual(prepared, "Really???")

    def test_medorbit_transliteration_still_applies_after_normalization(self):
        prepared = tts._prepare_text("مرحبًا من MedOrbit!!!", "ar")
        self.assertIn("ميد أوربِت", prepared)
        self.assertNotIn("MedOrbit", prepared)


# ===========================================================================
# 6. SynthesisConfig plumbing is a verified no-op unless configured
# ===========================================================================

class TestSynthesisConfigIsOptInOnly(unittest.TestCase):
    def test_no_env_vars_set_returns_none(self):
        with mock.patch.object(tts, "_AR_LENGTH_SCALE", None), \
             mock.patch.object(tts, "_AR_NOISE_SCALE", None), \
             mock.patch.object(tts, "_AR_NOISE_W_SCALE", None):
            self.assertIsNone(tts._synthesis_config_for("ar"))

    def test_english_never_gets_a_synthesis_config(self):
        with mock.patch.object(tts, "_AR_LENGTH_SCALE", "0.9"):
            self.assertIsNone(tts._synthesis_config_for("en"))

    def test_setting_one_env_var_builds_a_config_with_others_left_none(self):
        with mock.patch.object(tts, "_AR_LENGTH_SCALE", "0.9"), \
             mock.patch.object(tts, "_AR_NOISE_SCALE", None), \
             mock.patch.object(tts, "_AR_NOISE_W_SCALE", None):
            config = tts._synthesis_config_for("ar")

        self.assertIsNotNone(config)
        self.assertEqual(config.length_scale, 0.9)
        self.assertIsNone(config.noise_scale)
        self.assertIsNone(config.noise_w_scale)

    def test_sentence_silence_field_does_not_exist_on_installed_piper(self):
        """Documents this batch's verified finding: VD_TTS_SENTENCE_SILENCE
        was requested but piper-tts==1.6.0's SynthesisConfig has no field it
        could map to (speaker_id, length_scale, noise_scale, noise_w_scale,
        normalize_audio, volume only) — deliberately not implemented rather
        than guessed at."""
        from piper import SynthesisConfig
        import dataclasses

        field_names = {f.name for f in dataclasses.fields(SynthesisConfig)}
        self.assertNotIn("sentence_silence", field_names)
        self.assertEqual(
            field_names,
            {"speaker_id", "length_scale", "noise_scale", "noise_w_scale",
             "normalize_audio", "volume"},
        )


if __name__ == "__main__":
    unittest.main()
