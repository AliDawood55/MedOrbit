% Virtual Doctor — symbolic interview reasoning (Phase 2).
%
% Decides WHAT clinical topic to ask next. It never decides HOW to word it:
% a topic here is an atom like `duration`, never a sentence. Natural wording
% is generated in Python/LLM, downstream, and clamped back to the topic chosen
% here.
%
% WHAT THIS IS A MIGRATION OF
% ---------------------------
% interview_engine._next_unfilled_slot: walk the active complaint's slots in
% the order flows/*.json declares them, take the first the profile has not
% filled. That behaviour is characterized in
% tests/test_characterization_interview_flows.py and reproduced here.
%
% flows/*.json REMAINS THE SOURCE OF TRUTH. The slot vocabulary and its order
% are not restated in this file — they arrive as required_slot/optional_slot
% facts built from the flow the application already loaded. That is why there
% is no table of complaints here, and why editing a flow file still changes
% the interview.
%
% NO SAFETY VERDICTS HERE. safety_topic/2 may raise a topic's PRIORITY when the
% deterministic Python layer already flagged the turn, but nothing in this file
% computes, changes or contributes to urgency. That is Phase 3, in safety.pl.

:- dynamic(vd_fact/4).

% --- fact accessors ---------------------------------------------------------

required_slot(S, Slot, Position) :- vd_fact(S, required_slot, Slot, Position).
optional_slot(S, Slot, Position) :- vd_fact(S, optional_slot, Slot, Position).

% Every slot the active flow declares, required or not.
flow_slot(S, Slot, Position) :- required_slot(S, Slot, Position).
flow_slot(S, Slot, Position) :- optional_slot(S, Slot, Position).

asked(S, Slot)        :- vd_fact(S, asked, Slot, true).
intake_known(S, Field) :- vd_fact(S, intake, Field, true).

% Set by Python when the deterministic safety layer flagged this turn. An
% input to ordering only — see the header.
safety_topic(S, Topic) :- vd_fact(S, safety_topic, Topic, true).

% --- knowledge state --------------------------------------------------------

% NOT named unanswered/2: base.pl already owns that name for the broader
% "a slot in the tracked vocabulary has no answer" (over expected_slot/2), and
% redefining it here would silently change Phase 1's knowledge-state output.
% Two genuinely different questions, so two predicates:
%
%   base.pl      unanswered/2   — of everything we track, what is unfilled?
%   interview.pl outstanding/2  — of what THIS FLOW requires, what is missing?
outstanding(S, Slot) :- required_slot(S, Slot, _), \+ answered(S, Slot).

% Asked but not answered: the patient said something that did not fill the
% slot. Recorded and queryable for observability. Deliberately NOT used to
% gate relevant_question/2 — the current application re-offers such a topic,
% and Phase 2 preserves that. Changing it would change when interviews end.
asked_unanswered(S, Slot) :- asked(S, Slot), \+ answered(S, Slot).

% --- dependencies -----------------------------------------------------------
% depends_on(Topic, Condition): Topic is relevant only while Condition holds.
% Conditions are resolved by holds/2, and a condition with no holds/2 clause
% never holds — an unknown dependency fails CLOSED (topic not asked) rather
% than open.
%
% Exactly one dependency exists in the application today, and it applies to
% every clinical topic: intake (name, then age) precedes every clinical
% question — planner._intake_turn and interview_engine._next_intake_reply.
% Written as one clause over all topics rather than ten near-identical rows.
%
% No CLINICAL dependency is declared here. Today a topic's relevance is decided
% entirely by which flow lists it (characterized: flow slots carry no condition
% field), so adding one would be new medical behaviour, not a migration. The
% mechanism is general so Phase 3 can add e.g.
% depends_on(radiation, symptom(chest_pain)).

:- discontiguous(depends_on/2).

depends_on(_, intake_complete).

holds(S, intake_complete) :- intake_known(S, name), patient_attr(S, age, _).

dependencies_met(S, Topic) :- forall(depends_on(Topic, C), holds(S, C)).

% --- relevance --------------------------------------------------------------
% A topic is worth asking when the active flow declares it, it has not been
% answered, and its dependencies hold. Topics the flow does not declare are
% never relevant, however much of the vocabulary exists — which is what stops
% `radiation` being asked during a headache consultation.

relevant_question(S, Topic) :-
    flow_slot(S, Topic, _),
    \+ answered(S, Topic),
    dependencies_met(S, Topic).

% --- priority ---------------------------------------------------------------
% Lower number is asked sooner. Two bands, so ordering is total and stable:
%
%   0..99     safety-indicated topics — a red flag the deterministic layer
%             already detected gets explored before routine questions. This
%             makes deterministic what PlannerInput.safety_hint previously
%             only nudged the LLM towards.
%   100..199  ordinary flow topics, in the order flows/*.json declares them.
%
% Within a band the flow's own position decides, so the migrated ordering is
% identical to _next_unfilled_slot whenever no safety topic is indicated.

safety_band(0).
normal_band(100).

question_priority(S, Topic, Priority) :-
    relevant_question(S, Topic),
    flow_slot(S, Topic, Position),
    (   safety_topic(S, Topic)
    ->  safety_band(Band)
    ;   normal_band(Band)
    ),
    Priority is Band + Position.

% --- selection --------------------------------------------------------------
% Sorted on Priority-Topic pairs, so equal priorities break by topic name in
% standard order: reproducible across runs and across machines, which is what
% makes the divergence logs and the tests meaningful. sort/4 with @=< keeps
% duplicates, so no candidate is silently dropped.

next_question(S, Topic) :-
    findall(P-T, question_priority(S, T, P), Pairs),
    Pairs \== [],
    sort(0, @=<, Pairs, [_-Topic|_]).

% The full ranked list, for divergence logging and for tests that need to see
% the ordering rather than just its head.
ranked_questions(S, Topics) :-
    findall(P-T, question_priority(S, T, P), Pairs),
    sort(0, @=<, Pairs, Sorted),
    findall(T, member(_-T, Sorted), Topics).

% --- completion -------------------------------------------------------------
% Complete when a flow is actually active, intake is done, and no REQUIRED slot
% is outstanding. Deliberately built on unanswered/2, which ignores
% dependencies: an unmet dependency must never be able to make an interview
% look finished. Optional slots never block completion.

interview_complete(S) :-
    holds(S, intake_complete),
    required_slot(S, _, _),
    \+ outstanding(S, _).
