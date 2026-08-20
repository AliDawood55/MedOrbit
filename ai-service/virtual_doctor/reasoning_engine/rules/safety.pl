% Virtual Doctor — symbolic clinical safety reasoning (Phase 3).
%
% Static application code. Patient text never becomes a rule and never becomes
% a rule id: Python asserts only vd_fact/4 rows whose every argument has passed
% the vocabulary allow-list, and every RuleId below is a constant written here.
%
% THIS FILE IS NOT THE SAFETY FLOOR
% ---------------------------------
% chatbot/nlu/safety.py MedicalSafetyLayer runs FIRST, on raw patient text, and
% is permanent. Its verdict arrives here as deterministic_urgency/3 (base.pl)
% and final_urgency/2 is a maximum, so nothing in this file can lower it. The
% two layers do different jobs:
%
%   MedicalSafetyLayer   raw-language emergency floor — catches a dangerous
%                        PHRASE ("صداع شديد فجأة") including ones no structured
%                        fact represents. Its 38 regexes are NOT copied here.
%   safety.pl            combinational reasoning over validated STRUCTURED
%                        facts — catches a dangerous COMBINATION that no single
%                        phrase states.
%
% WHY THESE RULES AND NO OTHERS
% -----------------------------
% Phase 3 is a consolidation, not an expansion of medical knowledge. Every rule
% below restates urgency MedOrbit already assigns somewhere — MedicalSafetyLayer
% patterns or SymptomSpecialtyEngine.EMERGENCY_KEYWORDS — applied to structured
% facts instead of only to raw phrasing. The provenance of each is named on the
% rule.
%
% Two things are deliberately ABSENT, and the absence is load-bearing:
%
%   * No rule keys on `headache` alone or on headache + a common associated
%     symptom. tests/test_characterization_safety_matrix.py records that the
%     extractor DOES emit ['headache'] and ['headache','nausea'] for cases this
%     system pins as routine. A rule on either would escalate a pinned-routine
%     case, so there is none.
%   * No rule keys on `chest_pain` alone. Arabic "الم صدر" already reaches
%     emergency through MedicalSafetyLayer, but English "chest pain" is
%     currently routine; making the symptom alone an emergency would change
%     English behaviour with no pinned basis for it. Chest pain escalates here
%     only in COMBINATION — with dyspnea, or with a severe severity answer.
%
% ONSET IS NOT AVAILABLE. There is no `onset` slot in flows/*.json, so
% "sudden" is not a structured fact and thunderclap-headache reasoning cannot
% be expressed here. MedicalSafetyLayer covers it from raw text, which is
% exactly the division of labour above.

:- dynamic(vd_fact/4).

% --- extending base.pl ------------------------------------------------------
% urgency/2 is declared discontiguous+multifile in base.pl precisely so this
% file can add clauses rather than redefine the predicate. The declaration is
% repeated here because SWI-Prolog requires it in EVERY file that contributes
% clauses — without it, consulting this file would replace base.pl's clause
% instead of joining it, silently dropping the deterministic floor. That is the
% same failure mode that hit unanswered/2 in Phase 2, caught there by a consult
% warning; here it would be a safety regression, so it is also asserted by a
% test rather than left to a warning nobody reads.
:- discontiguous(urgency/2).
:- multifile(urgency/2).

% base.pl's final_urgency/2 already takes the maximum over every urgency/2
% solution, so adding a clause here can only ever RAISE a verdict.
urgency(S, U) :- red_flag(S, U, _, _).

% --- symptom classes --------------------------------------------------------
% Small, closed, and named so the rules below read clinically rather than as
% long disjunctions. Members are canonical atoms from vocabulary.SYMPTOMS.

pain_symptom(chest_pain).
pain_symptom(headache).
pain_symptom(stomach_pain).
pain_symptom(stomach_ache).
pain_symptom(back_pain).
pain_symptom(flank_pain).

% Severity as answered in the interview. Slot-level, not per-symptom: the
% current data model has one `severity` slot per consultation rather than an
% attribute per symptom, so a severity answer is read against the consultation
% it belongs to. Recorded as a known limitation rather than papered over with
% invented per-symptom precision.
severe_reported(S) :- slot_value(S, severity, severe).

% --- red flags --------------------------------------------------------------
% red_flag(Session, Urgency, RuleId, Evidence).
%
% Evidence is a list of canonical atoms, ordered as written so a rule's trace is
% byte-identical run to run. RuleId is a constant; it is for audit and is never
% shown to a patient.

% EMERGENCY -----------------------------------------------------------------

% Chest pain with breathlessness. The canonical combinational case: each half
% is individually unremarkable in a structured record, together they are not.
% Provenance: both are emergency patterns in MedicalSafetyLayer, and
% SymptomSpecialtyEngine lists "difficulty breathing".
red_flag(S, emergency, chest_pain_with_dyspnea, [chest_pain, shortness_of_breath]) :-
    symptom(S, chest_pain),
    symptom(S, shortness_of_breath).

% Breathlessness alone. Provenance: MedicalSafetyLayer EMERGENCY patterns
% "ضيق تنفس" / "صعوبة تنفس", and SymptomSpecialtyEngine "difficulty breathing".
red_flag(S, emergency, dyspnea, [shortness_of_breath]) :-
    symptom(S, shortness_of_breath).

% Provenance: MedicalSafetyLayer "فقدان الوعي" / "unconscious";
% SymptomSpecialtyEngine "unconscious" / "فقدان الوعي".
red_flag(S, emergency, unconscious, [unconscious]) :-
    symptom(S, unconscious).

% Provenance: MedicalSafetyLayer "نزيف شديد" / "severe bleeding";
% SymptomSpecialtyEngine "severe bleeding" / "نزيف حاد".
red_flag(S, emergency, severe_bleeding, [severe_bleeding]) :-
    symptom(S, severe_bleeding).

% Severe chest pain. Provenance: SymptomSpecialtyEngine's emergency keywords
% "severe chest pain" / "ألم صدري حاد" — the same rule, reached through the
% severity ANSWER rather than through the patient happening to use that phrase.
red_flag(S, emergency, severe_chest_pain, [chest_pain, severe]) :-
    symptom(S, chest_pain),
    severe_reported(S).

% URGENT --------------------------------------------------------------------

% Provenance: MedicalSafetyLayer URGENT patterns for hematuria
% ("دم في البول" and three variants).
red_flag(S, urgent, hematuria, [hematuria]) :-
    symptom(S, hematuria).

% Provenance: MedicalSafetyLayer URGENT "تشنج|نوبة صرع|صرع" / "seizure".
red_flag(S, urgent, seizure, [seizure]) :-
    symptom(S, seizure).

% Severe pain of any kind. Provenance: MedicalSafetyLayer URGENT "الم شديد" /
% "severe pain" — again the same rule reached from the severity answer rather
% than from raw phrasing. Chest pain also matches severe_chest_pain above at
% emergency; final_urgency/2 takes the maximum, so the stronger verdict wins
% while both traces survive.
red_flag(S, urgent, severe_pain, [Symptom, severe]) :-
    pain_symptom(Symptom),
    symptom(S, Symptom),
    severe_reported(S).

% --- evidence ---------------------------------------------------------------
% Every rule that fired, with its urgency and evidence. Sorted so repeated runs
% and repeated queries produce byte-identical traces — a trace that reorders
% between runs is not auditable.

safety_evidence(S, RuleId, Urgency, Evidence) :-
    red_flag(S, Urgency, RuleId, Evidence).

all_safety_evidence(S, Sorted) :-
    findall(RuleId-Urgency-Evidence, red_flag(S, Urgency, RuleId, Evidence), Raw),
    sort(Raw, Sorted).

% The single most severe symbolic verdict, with the rule that justifies it.
% Sorted on Rank-RuleId-Urgency-Evidence in standard order, so equal-severity
% rules break deterministically on rule id and the chosen exemplar never varies
% between runs.
top_red_flag(S, Urgency, RuleId, Evidence) :-
    findall(Rank-RuleId0-Urgency0-Evidence0,
            ( red_flag(S, Urgency0, RuleId0, Evidence0),
              urgency_rank(Urgency0, Rank) ),
            Raw),
    Raw \== [],
    sort(0, @>=, Raw, [_-RuleId-Urgency-Evidence|_]).

% Symbolic-only urgency: what THIS file concludes, ignoring the deterministic
% floor. Kept separate from final_urgency/2 so shadow mode can report what the
% symbolic layer contributed on its own, and so a test can prove the floor is
% doing the work rather than the rules coincidentally agreeing.
symbolic_urgency(S, U) :-
    findall(R-X, (red_flag(S, X, _, _), urgency_rank(X, R)), Pairs),
    (   Pairs == []
    ->  U = routine
    ;   sort(0, @>=, Pairs, [_-U|_])
    ).
