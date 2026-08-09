% Virtual Doctor — base symbolic layer (Phase 1).
%
% Static application code. Patient text never becomes a rule, and nothing here
% is generated at runtime: Python only ever asserts vd_fact/4 rows whose every
% argument has already passed the vocabulary allow-list.
%
% ONE FACT SHAPE, MANY ACCESSORS
% ------------------------------
% Everything is vd_fact(Session, Predicate, Subject, Value). The readable
% predicates below are projections of it. That keeps the Python side to a
% single validated writer, and lets later phases add clinical rules without
% adding new Python code paths.
%
% SCOPE
% -----
% Phase 1 only: fact accessors, the canonical urgency lattice, and knowledge
% state. There are deliberately NO red-flag, interview, contradiction or
% differential rules here — those arrive with safety.pl / interview.pl /
% contradictions.pl / differential.pl in their own phases.

:- dynamic(vd_fact/4).

% --- fact accessors ---------------------------------------------------------

symptom(S, X)           :- vd_fact(S, symptom, X, present).
denies(S, X)            :- vd_fact(S, symptom, X, absent).
uncertain_symptom(S, X) :- vd_fact(S, symptom, X, uncertain).

slot_value(S, Slot, V)  :- vd_fact(S, slot, Slot, V).
patient_attr(S, K, V)   :- vd_fact(S, patient_attr, K, V).
complaint(S, C)         :- vd_fact(S, complaint, C, active).

answered(S, Slot)       :- vd_fact(S, answered, Slot, true).

% The deterministic Python floor (MedicalSafetyLayer), asserted as a fact.
% Prolog reads it; Prolog never replaces it. See final_urgency/2.
deterministic_urgency(S, U, Rule) :- vd_fact(S, deterministic_urgency, Rule, U).

% --- the one canonical urgency lattice --------------------------------------
% routine < urgent < emergency. Mirrors vocabulary.URGENCY_RANK; a test asserts
% the two agree. "normal" is translated to routine on the Python side and never
% appears here, so there is exactly one ordering in the symbolic layer.

urgency_rank(routine, 1).
urgency_rank(urgent, 2).
urgency_rank(emergency, 3).

% Every urgency opinion available this turn. Phase 1 has exactly one source:
% the deterministic floor. Phase 3's safety.pl adds red-flag clauses, which is
% why this is declared discontiguous/multifile now — so that file can extend
% urgency/2 rather than silently redefining it.
:- discontiguous(urgency/2).
:- multifile(urgency/2).

urgency(S, U) :- deterministic_urgency(S, U, _).

% ESCALATION-ONLY, BY CONSTRUCTION. final_urgency/2 is a maximum over the
% lattice, so no clause added in a later phase can lower a verdict another
% clause already reached — the worst a wrong rule can do is fail to raise.
% Invariant S13.
final_urgency(S, U) :-
    findall(R-X, (urgency(S, X), urgency_rank(X, R)), Pairs),
    (   Pairs == []
    ->  U = routine
    ;   sort(0, @>=, Pairs, [_-U|_])
    ).

% Which rules produced the winning level — the evidence trace behind a verdict.
urgency_evidence(S, U, Rule) :- deterministic_urgency(S, U, Rule).

% --- knowledge state --------------------------------------------------------

known(S, Slot) :- slot_value(S, Slot, _).
known(S, Slot) :- patient_attr(S, Slot, _).

unanswered(S, Slot) :- vd_fact(S, expected_slot, Slot, true), \+ answered(S, Slot).

% --- introspection ----------------------------------------------------------
% Used by the shadow-mode measurement and by the session-isolation tests.

session_fact_count(S, N) :- aggregate_all(count, vd_fact(S, _, _, _), N).
