
:- dynamic(vd_fact/4).

:- discontiguous(urgency/2).
:- multifile(urgency/2).

urgency(S, U) :- red_flag(S, U, _, _).


pain_symptom(chest_pain).
pain_symptom(headache).
pain_symptom(stomach_pain).
pain_symptom(stomach_ache).
pain_symptom(back_pain).
pain_symptom(flank_pain).

severe_reported(S) :- slot_value(S, severity, severe).



red_flag(S, emergency, chest_pain_with_dyspnea, [chest_pain, shortness_of_breath]) :-
    symptom(S, chest_pain),
    symptom(S, shortness_of_breath).

red_flag(S, emergency, dyspnea, [shortness_of_breath]) :-
    symptom(S, shortness_of_breath).

red_flag(S, emergency, unconscious, [unconscious]) :-
    symptom(S, unconscious).

red_flag(S, emergency, severe_bleeding, [severe_bleeding]) :-
    symptom(S, severe_bleeding).

red_flag(S, emergency, severe_chest_pain, [chest_pain, severe]) :-
    symptom(S, chest_pain),
    severe_reported(S).


red_flag(S, urgent, hematuria, [hematuria]) :-
    symptom(S, hematuria).

red_flag(S, urgent, seizure, [seizure]) :-
    symptom(S, seizure).

red_flag(S, urgent, severe_pain, [Symptom, severe]) :-
    pain_symptom(Symptom),
    symptom(S, Symptom),
    severe_reported(S).


safety_evidence(S, RuleId, Urgency, Evidence) :-
    red_flag(S, Urgency, RuleId, Evidence).

all_safety_evidence(S, Sorted) :-
    findall(RuleId-Urgency-Evidence, red_flag(S, Urgency, RuleId, Evidence), Raw),
    sort(Raw, Sorted).

top_red_flag(S, Urgency, RuleId, Evidence) :-
    findall(Rank-RuleId0-Urgency0-Evidence0,
            ( red_flag(S, Urgency0, RuleId0, Evidence0),
              urgency_rank(Urgency0, Rank) ),
            Raw),
    Raw \== [],
    sort(0, @>=, Raw, [_-RuleId-Urgency-Evidence|_]).

symbolic_urgency(S, U) :-
    findall(R-X, (red_flag(S, X, _, _), urgency_rank(X, R)), Pairs),
    (   Pairs == []
    ->  U = routine
    ;   sort(0, @>=, Pairs, [_-U|_])
    ).
