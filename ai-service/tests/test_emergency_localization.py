"""Focused regressions for Palestinian medical emergency localization."""

import os
import sys
import unittest


sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from chatbot.nlu.safety import MedicalSafetyLayer
from virtual_doctor.interview_engine import _check_safety


class TestEmergencyLocalization(unittest.TestCase):
    def setUp(self):
        self.safety = MedicalSafetyLayer()

    def test_arabic_emergency_chatbot_response_uses_palestinian_red_crescent_101(self):
        result = self.safety.check("طوارئ")

        self.assertEqual(result["severity"], "emergency")
        self.assertIn("الهلال الأحمر الفلسطيني", result["response"])
        self.assertIn("نابلس", result["response"])
        self.assertIn("الضفة الغربية", result["response"])
        self.assertIn("101", result["response"])

    def test_english_emergency_chatbot_response_uses_palestinian_red_crescent_101(self):
        result = self.safety.check("emergency")

        self.assertEqual(result["severity"], "emergency")
        self.assertIn("Palestinian Red Crescent ambulance service", result["response"])
        self.assertIn("Nablus", result["response"])
        self.assertIn("West Bank", result["response"])
        self.assertIn("101", result["response"])
        self.assertNotIn("911", result["response"])

    def test_arabic_virtual_doctor_emergency_response_uses_palestinian_red_crescent_101(self):
        result = _check_safety("طوارئ", "ar")

        self.assertEqual(result["severity"], "emergency")
        self.assertIn("الهلال الأحمر الفلسطيني", result["response"])
        self.assertIn("نابلس", result["response"])
        self.assertIn("الضفة الغربية", result["response"])
        self.assertIn("101", result["response"])

    def test_english_virtual_doctor_emergency_response_uses_palestinian_red_crescent_101(self):
        result = _check_safety("emergency", "en")

        self.assertEqual(result["severity"], "emergency")
        self.assertIn("Palestinian Red Crescent ambulance service", result["response"])
        self.assertIn("Nablus", result["response"])
        self.assertIn("West Bank", result["response"])
        self.assertIn("101", result["response"])
        self.assertNotIn("911", result["response"])

    def test_urgent_response_behavior_is_unchanged_for_both_consumers(self):
        expected_response = (
            "⚠️ **Urgent Medical Attention Recommended**\n\n"
            "This condition requires prompt medical attention. "
            "Please visit the nearest clinic or medical center.\n\n"
            "💡 I can help you find the nearest healthcare facility."
        )

        chatbot_result = self.safety.check("high fever")
        virtual_doctor_result = _check_safety("high fever", "en")

        for result in (chatbot_result, virtual_doctor_result):
            self.assertFalse(result["is_emergency"])
            self.assertTrue(result["is_urgent"])
            self.assertEqual(result["severity"], "urgent")
            self.assertEqual(result["response"], expected_response)
            self.assertFalse(result["bypass_intent_routing"])

    def test_non_emergency_response_behavior_is_unchanged_for_both_consumers(self):
        expected = {
            "is_emergency": False,
            "is_urgent": False,
            "severity": "normal",
            "matched_patterns": [],
            "response": None,
            "bypass_intent_routing": False,
        }

        self.assertEqual(self.safety.check("I need a doctor appointment"), expected)
        self.assertEqual(_check_safety("I need a doctor appointment", "en"), expected)


if __name__ == "__main__":
    unittest.main()
