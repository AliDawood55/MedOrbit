% Virtual Doctor — symbolic contradiction and correction reasoning (Phase 4).
%
% Static application code. No raw patient text reaches this file, and no
% Arabic parsing happens here: understanding "عمري 24 مش 23" stays in Python's
% existing correction layer, which produces a normalised candidate. This file
% reasons about the RESULT.
%
% NAMES NEVER BECOME ATOMS
% ------------------------
% A patient's name is arbitrary free text, so it cannot be an atom and the
% allow-list is not widened to admit it. It does not need to be: the only
% question asked of such a value here is "is it the same as that one?", which a
% stable opaque token (`v_<hex>`, see vocabulary.value_token) answers exactly as
% well. Ages stay integers and canonical slot values stay atoms, because those
% are already safe and are far more useful in an evidence trace.
%
% ONE GENERAL RULE, NOT ONE PER FIELD
% -----------------------------------
% There is no age_contradiction/2 or name_contradiction/2. There is
% contradiction/6 over single_valued/1, so adding a field is a slot declaration
% rather than a new rule — which is the whole point of the migration.
%
% THREE CATEGORIES THAT LOOK ALIKE IN TEXT
% ----------------------------------------
% Characterized in tests/test_characterization_correction_matrix.py and kept
% apart here, because collapsing them is the obvious wrong turn:
%
%   identity slot changed   -> a stored value is wrong        -> correction
%   clinical slot changed   -> the patient's state is updated -> NOT a correction
%   symptom present/absent  -> clinical information           -> NOT a correction
%
% "no, I don't have a fever" and "my age is 24, not 23" both contain a negation.
% Only the second asks for a stored value to be replaced.

:- dynamic(vd_stated/4).
:- dynamic(vd_fact/4).

% --- provenance -------------------------------------------------------------
% stated(Session, Slot, Value, Turn). Turn is a logical message ordinal derived
% from correction_history order, never a wall clock — ordering must be
% reproducible when the same session is rebuilt from the database.

stated(S, Slot, Value, Turn) :- vd_stated(S, Slot, Value, Turn).

% A candidate is this turn's proposed value, carried as an ordinary statement
% at the highest turn index so the general rules apply to it unchanged.
correction_candidate_slot(S, Slot) :- vd_fact(S, correction_candidate, Slot, true).

% --- slot cardinality -------------------------------------------------------
% Identity/demographic slots the correction layer actually maintains today.
identity_slot(name).
identity_slot(age).
identity_slot(sex).
identity_slot(chief_complaint).

% Clinical slots are also single-valued in storage — a later answer overwrites
% an earlier one — but a change to one is an UPDATE, not a correction of a
% wrong record. Declared so the distinction is expressible rather than assumed.
clinical_slot(duration).
clinical_slot(severity).
clinical_slot(location).
clinical_slot(location_character).
clinical_slot(character).
clinical_slot(radiation).
clinical_slot(triggers).
clinical_slot(appearance).
clinical_slot(exposure).

% Explicitly NOT single-valued. A patient accumulating symptoms is not
% contradicting themselves, and marking this single-valued would make every new
% symptom read as a conflict.
multi_valued(associated_symptoms).

single_valued(Slot) :- identity_slot(Slot).
single_valued(Slot) :- clinical_slot(Slot).

% --- statement ordering -----------------------------------------------------

latest_statement(S, Slot, Value, Turn) :-
    findall(T-V, stated(S, Slot, V, T), Pairs),
    Pairs \== [],
    sort(0, @>=, Pairs, [Turn-Value|_]).

previous_statement(S, Slot, Value, Turn) :-
    latest_statement(S, Slot, _, LatestTurn),
    findall(T-V, ( stated(S, Slot, V, T), T < LatestTurn ), Pairs),
    Pairs \== [],
    sort(0, @>=, Pairs, [Turn-Value|_]).

% --- contradiction ----------------------------------------------------------
% The one general rule. Both values must have been explicitly stated, the slot
% must be single-valued, the values must differ, and the newer must genuinely
% be newer. Sorting rather than comparing raw solution order makes the result
% independent of the order facts were asserted in.

contradiction(S, Slot, Old, New, OldTurn, NewTurn) :-
    single_valued(Slot),
    latest_statement(S, Slot, New, NewTurn),
    previous_statement(S, Slot, Old, OldTurn),
    Old \== New,
    NewTurn > OldTurn.

% --- classification ---------------------------------------------------------
% correction_kind(Session, Slot, Kind). Deliberately mutually exclusive so a
% slot maps to exactly one kind and the Python side never has to arbitrate.

% An identity slot whose stored value has been superseded: a real correction.
correction_kind(S, Slot, single_value_conflict) :-
    identity_slot(Slot),
    contradiction(S, Slot, _, _, _, _).

% A clinical slot that changed. Same shape, different meaning — the patient is
% telling us more, not telling us we recorded it wrongly.
correction_kind(S, Slot, clinical_state_update) :-
    clinical_slot(Slot),
    contradiction(S, Slot, _, _, _, _).

% Correction intent was detected for a slot, but nothing conflicts: either the
% same value was restated, or there is no prior value to replace.
correction_kind(S, Slot, no_contradiction) :-
    correction_candidate_slot(S, Slot),
    \+ contradiction(S, Slot, _, _, _, _).

% Intent without a field at all — "غلط" on its own. Python's clarification
% path handles it; this only names the state.
correction_kind(S, unknown_slot, ambiguous_correction) :-
    vd_fact(S, correction_intent, ambiguous, true).

% Intent with a field but no value that survived validation (an implausible age,
% a rejected name). Distinct from ambiguous: the field IS known.
correction_kind(S, Slot, uncertain_correction) :-
    vd_fact(S, correction_intent, unresolved, Slot),
    Slot \== ambiguous.

% --- evidence ---------------------------------------------------------------
% Sorted so a trace is byte-identical between runs and between assertion
% orders.

all_contradictions(S, Sorted) :-
    findall(Slot-Old-New-OldTurn-NewTurn,
            contradiction(S, Slot, Old, New, OldTurn, NewTurn), Raw),
    sort(Raw, Sorted).

all_correction_kinds(S, Sorted) :-
    findall(Slot-Kind, correction_kind(S, Slot, Kind), Raw),
    sort(Raw, Sorted).

% True when at least one identity slot genuinely conflicts — the symbolic
% answer to "is this turn a profile correction?".
profile_correction_indicated(S, Slot) :-
    correction_kind(S, Slot, single_value_conflict).
