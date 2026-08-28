"""
Phase 9 — dynamic consultation trajectories for interview-topic evaluation.

DETERMINISTIC AND DE-IDENTIFIED. Every trajectory is synthetic and written for
this file. No real consultation, no identifier.

WHY TRAJECTORIES RATHER THAN SINGLE TURNS
-----------------------------------------
Phase 2 proved static parity: given one profile, the symbolic planner picks the
same topic the static flow does. That says nothing about how a CONSULTATION
unfolds — whether facts accumulate correctly, whether an answered slot stays
answered, whether two patients with the same complaint diverge as their known
facts diverge. A trajectory is a sequence of profile states, so those are
exactly what it measures.

WHAT A TRAJECTORY IS
--------------------
A complaint, plus a list of turns. Each turn carries the profile as it stands
AFTER that turn's answer is stored, and the topic a correct planner should ask
next. `expected` is not a new clinical judgement: it is derived from the
flow's own declared slot order, which is the only source of interview knowledge
this system has. Where a turn is safety-flagged, `expected` follows the Phase 3
rule that the red-flag follow-up topic is explored first.

`None` as an expected topic means "the interview should be complete here".

WHAT THE GROUND TRUTH IS NOT
----------------------------
No new medical knowledge. There is no trajectory asserting that chest pain plus
dyspnea "should" prompt `radiation` sooner than the flow declares it, because
no rule in this system says so and inventing one here would be smuggling Phase
5 in through the benchmark. Where the flow order is the only answer, the flow
order is the expected answer.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

_INTAKE = {"name": "TEST_PATIENT", "age": 34}


def _turn(patient_says: str, profile: Dict[str, Any], expected: Optional[str],
          *, entities=None, safety=None, asked=(), note: str = "") -> Dict[str, Any]:
    return {
        "says": patient_says,
        "profile": {**_INTAKE, **profile},
        "entities": {"symptoms": list(entities or [])},
        "safety_flagged": safety,
        "asked_topics": list(asked),
        "expected_topic": expected,
        "note": note,
    }


def _traj(tid: str, complaint: str, turns: List[Dict[str, Any]],
          categories=()) -> Dict[str, Any]:
    return {"id": tid, "complaint": complaint, "categories": list(categories),
            "turns": turns}


TRAJECTORIES: List[Dict[str, Any]] = [

    _traj("chest_a", "chest_pain", [
        _turn("I have chest pain", {}, "duration", entities=["chest pain"]),
        _turn("It started two hours ago", {"duration": "two hours"}, "character",
              entities=["chest pain"]),
        _turn("It feels like pressure", {"duration": "two hours", "character": "pressure"},
              "radiation", entities=["chest pain"]),
        _turn("It goes into my left arm",
              {"duration": "two hours", "character": "pressure", "radiation": "left arm"},
              "associated_symptoms", entities=["chest pain"]),
        _turn("No other symptoms",
              {"duration": "two hours", "character": "pressure", "radiation": "left arm",
               "associated_symptoms": "none"}, None, entities=["chest pain"],
              note="all required slots filled -> complete"),
    ], ["linear"]),

    _traj("chest_b", "chest_pain", [
        _turn("I have severe chest pain and shortness of breath", {}, "duration",
              entities=["chest pain", "shortness of breath"]),
        _turn("Since this morning, it is a sharp pain",
              {"duration": "since this morning", "character": "sharp"}, "radiation",
              entities=["chest pain", "shortness of breath"],
              note="two slots filled in one answer -> skips character"),
        _turn("It does not spread anywhere",
              {"duration": "since this morning", "character": "sharp",
               "radiation": "no"}, "associated_symptoms",
              entities=["chest pain", "shortness of breath"]),
    ], ["multi_fill", "paired"]),

    _traj("chest_safety", "chest_pain", [
        _turn("I have crushing chest pain and I cannot breathe", {},
              "associated_symptoms", entities=["chest pain", "shortness of breath"],
              safety="emergency",
              note="safety band 0 pulls associated_symptoms ahead of duration"),
        _turn("Yes I am sweating too",
              {"associated_symptoms": "sweating"}, "duration",
              entities=["chest pain", "shortness of breath"], safety="emergency",
              note="once answered, ordinary flow order resumes"),
    ], ["safety"]),

    _traj("abd_a", "abdominal_pain", [
        _turn("My stomach hurts", {}, "duration", entities=["stomach pain"]),
        _turn("Three days", {"duration": "three days"}, "location_character",
              entities=["stomach pain"]),
        _turn("Lower right, cramping",
              {"duration": "three days", "location_character": "lower right cramping"},
              "associated_symptoms", entities=["stomach pain"]),
        _turn("I have been vomiting",
              {"duration": "three days", "location_character": "lower right cramping",
               "associated_symptoms": "vomiting"}, "triggers",
              entities=["stomach pain", "vomiting"]),
    ], ["linear"]),

    _traj("abd_b", "abdominal_pain", [
        _turn("Cramping pain in my lower abdomen since yesterday",
              {"duration": "since yesterday",
               "location_character": "lower abdomen cramping"},
              "associated_symptoms", entities=["stomach pain"],
              note="two slots volunteered up front -> skips both"),
        _turn("It gets worse after eating",
              {"duration": "since yesterday",
               "location_character": "lower abdomen cramping",
               "associated_symptoms": "none", "triggers": "after eating"},
              None, entities=["stomach pain"]),
    ], ["multi_fill", "paired"]),

    _traj("fev_a", "fever_cough", [
        _turn("I have a fever and a cough", {}, "duration", entities=["fever", "cough"]),
        _turn("Four days", {"duration": "four days"}, "severity",
              entities=["fever", "cough"]),
        _turn("It reached 39", {"duration": "four days", "severity": "39"},
              "associated_symptoms", entities=["fever", "cough"]),
        _turn("Sore throat as well",
              {"duration": "four days", "severity": "39",
               "associated_symptoms": "sore throat"}, "exposure",
              entities=["fever", "cough"]),
        _turn("My colleague was sick last week",
              {"duration": "four days", "severity": "39",
               "associated_symptoms": "sore throat", "exposure": "sick colleague"},
              None, entities=["fever", "cough"]),
    ], ["linear"]),

    _traj("fev_b", "fever_cough", [
        _turn("High fever for two days, very severe",
              {"duration": "two days", "severity": "severe"}, "associated_symptoms",
              entities=["fever"], note="paired with fev_a: different facts, different question"),
    ], ["multi_fill", "paired"]),

    _traj("head_a", "headache", [
        _turn("I have a headache", {}, "duration", entities=["headache"]),
        _turn("Since last night", {"duration": "since last night"}, "severity",
              entities=["headache"]),
        _turn("Moderate", {"duration": "since last night", "severity": "moderate"},
              "location", entities=["headache"]),
        _turn("On one side",
              {"duration": "since last night", "severity": "moderate",
               "location": "one side"}, "associated_symptoms", entities=["headache"]),
    ], ["linear"]),

    _traj("head_b", "headache", [
        _turn("Severe headache on the right side since this morning",
              {"duration": "since this morning", "severity": "severe",
               "location": "right side"}, "associated_symptoms",
              entities=["headache"],
              note="three slots in one utterance -> only one question left"),
        _turn("Yes, nausea",
              {"duration": "since this morning", "severity": "severe",
               "location": "right side", "associated_symptoms": "nausea"},
              None, entities=["headache", "nausea"]),
    ], ["multi_fill", "paired"]),

    _traj("head_correction", "headache", [
        _turn("Headache since yesterday, it is mild",
              {"duration": "since yesterday", "severity": "mild"}, "location",
              entities=["headache"]),
        _turn("Actually it is severe, not mild",
              {"duration": "since yesterday", "severity": "severe",
               "correction_history": [{"field": "severity", "old_value": "mild",
                                       "new_value": "severe"}]},
              "location", entities=["headache"],
              note="corrected field stays answered -> same next topic"),
    ], ["correction"]),

    _traj("head_unanswered", "headache", [
        _turn("I have a headache", {}, "duration", entities=["headache"]),
        _turn("I do not remember", {}, "duration", entities=["headache"],
              asked=["duration"],
              note="asked but not answered -> policy is to re-offer"),
    ], ["unanswered"]),

    _traj("rash_a", "rash", [
        _turn("I have a rash", {}, "duration", entities=["rash"]),
        _turn("Two weeks", {"duration": "two weeks"}, "appearance", entities=["rash"]),
        _turn("Red and raised", {"duration": "two weeks", "appearance": "red raised"},
              "location", entities=["rash"]),
        _turn("On my arms",
              {"duration": "two weeks", "appearance": "red raised",
               "location": "arms"}, "associated_symptoms", entities=["rash"]),
    ], ["linear"]),

    _traj("rash_b", "rash", [
        _turn("An itchy red rash on my legs for three days",
              {"duration": "three days", "appearance": "itchy red",
               "location": "legs"}, "associated_symptoms", entities=["rash"]),
    ], ["multi_fill", "paired"]),

    _traj("gen_a", "generic", [
        _turn("I feel unwell", {}, "duration"),
        _turn("A week", {"duration": "a week"}, "severity"),
        _turn("Mild", {"duration": "a week", "severity": "mild"},
              "associated_symptoms"),
        _turn("Nothing else",
              {"duration": "a week", "severity": "mild",
               "associated_symptoms": "none"}, None),
    ], ["linear"]),

    _traj("gen_safety", "generic", [
        _turn("I feel very unwell and I fainted", {}, "associated_symptoms",
              safety="emergency",
              note="safety topic first even on the generic flow"),
    ], ["safety"]),

    _traj("intake_missing", "headache", [
        {"says": "I have a headache", "profile": {"name": "TEST_PATIENT"},
         "entities": {"symptoms": ["headache"]}, "safety_flagged": None,
         "asked_topics": [], "expected_topic": None,
         "note": "age missing -> intake_complete fails -> no clinical topic is relevant"},
    ], ["intake"]),
]


PAIRS = (
    ("chest_a", "chest_b", 1),
    ("abd_a", "abd_b", 0),
    ("fev_a", "fev_b", 0),
    ("head_a", "head_b", 0),
    ("rash_a", "rash_b", 0),
)


def total_turns() -> int:
    return sum(len(t["turns"]) for t in TRAJECTORIES)


def by_complaint() -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for trajectory in TRAJECTORIES:
        counts[trajectory["complaint"]] = counts.get(trajectory["complaint"], 0) + 1
    return counts
