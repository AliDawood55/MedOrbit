
:- dynamic(vd_stated/4).
:- dynamic(vd_fact/4).


stated(S, Slot, Value, Turn) :- vd_stated(S, Slot, Value, Turn).

correction_candidate_slot(S, Slot) :- vd_fact(S, correction_candidate, Slot, true).

identity_slot(name).
identity_slot(age).
identity_slot(sex).
identity_slot(chief_complaint).

clinical_slot(duration).
clinical_slot(severity).
clinical_slot(location).
clinical_slot(location_character).
clinical_slot(character).
clinical_slot(radiation).
clinical_slot(triggers).
clinical_slot(appearance).
clinical_slot(exposure).

multi_valued(associated_symptoms).

single_valued(Slot) :- identity_slot(Slot).
single_valued(Slot) :- clinical_slot(Slot).


latest_statement(S, Slot, Value, Turn) :-
    findall(T-V, stated(S, Slot, V, T), Pairs),
    Pairs \== [],
    sort(0, @>=, Pairs, [Turn-Value|_]).

previous_statement(S, Slot, Value, Turn) :-
    latest_statement(S, Slot, _, LatestTurn),
    findall(T-V, ( stated(S, Slot, V, T), T < LatestTurn ), Pairs),
    Pairs \== [],
    sort(0, @>=, Pairs, [Turn-Value|_]).


contradiction(S, Slot, Old, New, OldTurn, NewTurn) :-
    single_valued(Slot),
    latest_statement(S, Slot, New, NewTurn),
    previous_statement(S, Slot, Old, OldTurn),
    Old \== New,
    NewTurn > OldTurn.


correction_kind(S, Slot, single_value_conflict) :-
    identity_slot(Slot),
    contradiction(S, Slot, _, _, _, _).

correction_kind(S, Slot, clinical_state_update) :-
    clinical_slot(Slot),
    contradiction(S, Slot, _, _, _, _).

correction_kind(S, Slot, no_contradiction) :-
    correction_candidate_slot(S, Slot),
    \+ contradiction(S, Slot, _, _, _, _).

correction_kind(S, unknown_slot, ambiguous_correction) :-
    vd_fact(S, correction_intent, ambiguous, true).

correction_kind(S, Slot, uncertain_correction) :-
    vd_fact(S, correction_intent, unresolved, Slot),
    Slot \== ambiguous.


all_contradictions(S, Sorted) :-
    findall(Slot-Old-New-OldTurn-NewTurn,
            contradiction(S, Slot, Old, New, OldTurn, NewTurn), Raw),
    sort(Raw, Sorted).

all_correction_kinds(S, Sorted) :-
    findall(Slot-Kind, correction_kind(S, Slot, Kind), Raw),
    sort(Raw, Sorted).

profile_correction_indicated(S, Slot) :-
    correction_kind(S, Slot, single_value_conflict).
