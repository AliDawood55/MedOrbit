
:- dynamic(vd_fact/4).


required_slot(S, Slot, Position) :- vd_fact(S, required_slot, Slot, Position).
optional_slot(S, Slot, Position) :- vd_fact(S, optional_slot, Slot, Position).

flow_slot(S, Slot, Position) :- required_slot(S, Slot, Position).
flow_slot(S, Slot, Position) :- optional_slot(S, Slot, Position).

asked(S, Slot)        :- vd_fact(S, asked, Slot, true).
intake_known(S, Field) :- vd_fact(S, intake, Field, true).

safety_topic(S, Topic) :- vd_fact(S, safety_topic, Topic, true).


outstanding(S, Slot) :- required_slot(S, Slot, _), \+ answered(S, Slot).

asked_unanswered(S, Slot) :- asked(S, Slot), \+ answered(S, Slot).


:- discontiguous(depends_on/2).

depends_on(_, intake_complete).

holds(S, intake_complete) :- intake_known(S, name), patient_attr(S, age, _).

dependencies_met(S, Topic) :- forall(depends_on(Topic, C), holds(S, C)).


relevant_question(S, Topic) :-
    flow_slot(S, Topic, _),
    \+ answered(S, Topic),
    dependencies_met(S, Topic).


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


next_question(S, Topic) :-
    findall(P-T, question_priority(S, T, P), Pairs),
    Pairs \== [],
    sort(0, @=<, Pairs, [_-Topic|_]).

ranked_questions(S, Topics) :-
    findall(P-T, question_priority(S, T, P), Pairs),
    sort(0, @=<, Pairs, Sorted),
    findall(T, member(_-T, Sorted), Topics).


interview_complete(S) :-
    holds(S, intake_complete),
    required_slot(S, _, _),
    \+ outstanding(S, _).
