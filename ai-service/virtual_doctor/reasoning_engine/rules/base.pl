
:- dynamic(vd_fact/4).


symptom(S, X)           :- vd_fact(S, symptom, X, present).
denies(S, X)            :- vd_fact(S, symptom, X, absent).
uncertain_symptom(S, X) :- vd_fact(S, symptom, X, uncertain).

slot_value(S, Slot, V)  :- vd_fact(S, slot, Slot, V).
patient_attr(S, K, V)   :- vd_fact(S, patient_attr, K, V).
complaint(S, C)         :- vd_fact(S, complaint, C, active).

answered(S, Slot)       :- vd_fact(S, answered, Slot, true).

deterministic_urgency(S, U, Rule) :- vd_fact(S, deterministic_urgency, Rule, U).


urgency_rank(routine, 1).
urgency_rank(urgent, 2).
urgency_rank(emergency, 3).

:- discontiguous(urgency/2).
:- multifile(urgency/2).

urgency(S, U) :- deterministic_urgency(S, U, _).

final_urgency(S, U) :-
    findall(R-X, (urgency(S, X), urgency_rank(X, R)), Pairs),
    (   Pairs == []
    ->  U = routine
    ;   sort(0, @>=, Pairs, [_-U|_])
    ).

urgency_evidence(S, U, Rule) :- deterministic_urgency(S, U, Rule).


known(S, Slot) :- slot_value(S, Slot, _).
known(S, Slot) :- patient_attr(S, Slot, _).

unanswered(S, Slot) :- vd_fact(S, expected_slot, Slot, true), \+ answered(S, Slot).


session_fact_count(S, N) :- aggregate_all(count, vd_fact(S, _, _, _), N).
