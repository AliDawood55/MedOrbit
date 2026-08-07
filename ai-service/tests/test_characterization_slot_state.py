"""
Characterization tests for SlotFiller.conversation_states growth/collision behavior.

These tests exercise chatbot/nlu/slots.py directly (not via chatbot/main.py),
using str(hash(message))-style keys as a stand-in for arbitrary caller-supplied
conversation_id values. They pin two things:
  - SlotFiller.conversation_states is caller-keyed and content-agnostic: if a
    caller passes the same key twice (whatever that key's origin), the state
    is shared/merged -- this is inherent to any dict-keyed-by-caller-supplied-id
    design, not specific to any particular key-derivation strategy.
  - the bounded (max size + TTL + LRU eviction) storage behavior added in the
    SlotFiller State Bounding Implementation batch.

NOTE: As of the Chatbot Slot State Keying Implementation batch, chatbot/main.py
itself no longer derives its SlotFiller key from str(hash(message)) -- it now
uses req.conversation_id when supplied, falling back to a per-request UUID
otherwise. The str(hash(message))-based collision scenario below remains a
valid characterization of SlotFiller's own keying behavior (which is still
purely caller-supplied-key-based), but no longer describes how main.py's
/chat route derives that key in production.
"""
import time
import unittest
from unittest import mock

from chatbot.nlu.slots import SlotFiller


class TestSlotFillerStateKeying(unittest.TestCase):
    """Pins how conversation_states is keyed, given an arbitrary caller-supplied conversation_id."""

    def setUp(self):
        self.slots = SlotFiller()

    def test_conversation_states_keyed_by_arbitrary_string(self):
        # SlotFiller itself is agnostic to what the caller passes as conversation_id.
        self.slots.update_state("any-key", "find_doctor", {})
        self.assertIn("any-key", self.slots.conversation_states)

    def test_repeated_identical_message_reuses_same_key(self):
        message = "I need a cardiologist"
        key = str(hash(message))

        self.slots.update_state(key, "find_doctor", {"specialty": "cardiology"})
        self.slots.update_state(key, "find_doctor", {"location": "Nablus"})

        self.assertEqual(len(self.slots.conversation_states), 1)
        state = self.slots.conversation_states[key]
        self.assertEqual(state["filled_slots"]["specialty"], "cardiology")
        self.assertEqual(state["filled_slots"]["location"], "Nablus")

    def test_identical_message_from_different_logical_users_collides(self):
        """
        Two different callers (simulated here as two independent update_state
        sequences) sending the exact same message text end up sharing one
        state entry, because the key is derived only from message content
        (str(hash(message))), not from any per-user/per-session identifier.
        """
        message = "I need a doctor"
        key = str(hash(message))

        # "User A" sends this message and fills their specialty slot.
        self.slots.update_state(key, "find_doctor", {"specialty": "cardiology"})

        # "User B" happens to send the exact same message text.
        self.slots.update_state(key, "find_doctor", {"location": "Ramallah"})

        # Only one state exists, and it now contains a merge of both users' data.
        self.assertEqual(len(self.slots.conversation_states), 1)
        merged_state = self.slots.conversation_states[key]
        self.assertEqual(merged_state["filled_slots"]["specialty"], "cardiology")
        self.assertEqual(merged_state["filled_slots"]["location"], "Ramallah")

    def test_many_unique_messages_stay_within_bound_when_under_cap(self):
        """
        Regression test (was: unbounded growth). With MAX_CONVERSATION_STATES
        comfortably above the number of unique messages sent here,
        conversation_states grows by one entry per unique message and no
        eviction is needed yet.
        """
        num_messages = 500
        self.assertLess(num_messages, self.slots.MAX_CONVERSATION_STATES)

        for i in range(num_messages):
            message = f"unique message number {i}"
            key = str(hash(message))
            self.slots.update_state(key, "find_doctor", {"specialty": "cardiology"})

        self.assertEqual(len(self.slots.conversation_states), num_messages)

    def test_state_count_never_exceeds_max_conversation_states(self):
        """
        Regression test proving unbounded growth is fixed: inserting more
        unique conversations than MAX_CONVERSATION_STATES triggers LRU
        eviction, so conversation_states never grows past the cap.
        """
        num_messages = self.slots.MAX_CONVERSATION_STATES + 250

        for i in range(num_messages):
            key = f"conv-{i}"
            self.slots.update_state(key, "find_doctor", {"specialty": "cardiology"})

        self.assertLessEqual(len(self.slots.conversation_states), self.slots.MAX_CONVERSATION_STATES)
        self.assertEqual(len(self.slots.conversation_states), self.slots.MAX_CONVERSATION_STATES)

    def test_lru_eviction_removes_least_recently_used_first(self):
        """When the cap is exceeded, the conversation NOT recently touched is evicted first."""
        self.slots.MAX_CONVERSATION_STATES = 3
        self.slots.update_state("conv-1", "find_doctor", {"specialty": "cardiology"})
        self.slots.update_state("conv-2", "find_doctor", {"specialty": "dermatology"})
        self.slots.update_state("conv-3", "find_doctor", {"specialty": "neurology"})

        # Touch conv-1 again so conv-2 becomes the least-recently-used entry.
        self.slots.update_state("conv-1", "find_doctor", {"location": "Nablus"})

        # Inserting a 4th conversation should evict conv-2 (the LRU one).
        self.slots.update_state("conv-4", "find_doctor", {"specialty": "pediatrics"})

        self.assertIn("conv-1", self.slots.conversation_states)
        self.assertNotIn("conv-2", self.slots.conversation_states)
        self.assertIn("conv-3", self.slots.conversation_states)
        self.assertIn("conv-4", self.slots.conversation_states)

    def test_expired_state_is_evicted_on_next_access(self):
        """A conversation untouched beyond the TTL is evicted the next time any method runs."""
        self.slots.update_state("conv-old", "find_doctor", {"specialty": "cardiology"})
        self.assertIn("conv-old", self.slots.conversation_states)

        # Simulate the TTL having elapsed since the last touch.
        past = time.time() - (self.slots.CONVERSATION_STATE_TTL_SECONDS + 1)
        self.slots._state_last_access["conv-old"] = past

        # Any state-touching call should sweep expired entries first.
        state = self.slots.get_state_summary("conv-old")

        self.assertFalse(state["active"])
        self.assertNotIn("conv-old", self.slots.conversation_states)
        self.assertNotIn("conv-old", self.slots._state_last_access)

    def test_active_state_survives_normal_reads_within_ttl(self):
        """A conversation accessed within the TTL window is not evicted."""
        self.slots.update_state("conv-active", "find_doctor", {"specialty": "cardiology"})

        recent = time.time() - 10  # well within CONVERSATION_STATE_TTL_SECONDS
        self.slots._state_last_access["conv-active"] = recent

        state = self.slots.get_state_summary("conv-active")

        self.assertTrue(state["active"])
        self.assertIn("conv-active", self.slots.conversation_states)

    def test_repeated_access_refreshes_recency(self):
        """Reading/updating a conversation updates its last-access timestamp (LRU refresh)."""
        self.slots.update_state("conv-refresh", "find_doctor", {"specialty": "cardiology"})
        first_touch = self.slots._state_last_access["conv-refresh"]

        with mock.patch("chatbot.nlu.slots.time.time", return_value=first_touch + 100):
            self.slots.get_state_summary("conv-refresh")

        self.assertGreater(self.slots._state_last_access["conv-refresh"], first_touch)

    def test_clear_state_removes_single_entry_only(self):
        self.slots.update_state("key-a", "find_doctor", {"specialty": "cardiology"})
        self.slots.update_state("key-b", "find_doctor", {"specialty": "dermatology"})

        self.slots.clear_state("key-a")

        self.assertNotIn("key-a", self.slots.conversation_states)
        self.assertIn("key-b", self.slots.conversation_states)

    def test_clear_state_removes_private_lru_metadata(self):
        """clear_state must remove both the state and its _state_last_access entry."""
        self.slots.update_state("key-a", "find_doctor", {"specialty": "cardiology"})
        self.assertIn("key-a", self.slots._state_last_access)

        self.slots.clear_state("key-a")

        self.assertNotIn("key-a", self.slots.conversation_states)
        self.assertNotIn("key-a", self.slots._state_last_access)

    def test_clear_state_still_works_alongside_automatic_eviction(self):
        """
        clear_state() remains a manual, explicit removal path. Nothing in
        SlotFiller or in chatbot/main.py's call site invokes it automatically
        (confirmed by inspection -- main.py never calls slot_filler.clear_state),
        but as of this batch, TTL and LRU eviction now provide automatic bounding
        even though clear_state is never called in production.
        """
        self.slots.update_state("key-a", "find_doctor", {"specialty": "cardiology"})
        self.assertEqual(len(self.slots.conversation_states), 1)

        self.slots.clear_state("key-a")
        self.assertEqual(len(self.slots.conversation_states), 0)

        # Clearing a key that was never present is a no-op, not an error.
        self.slots.clear_state("never-existed")
        self.assertEqual(len(self.slots.conversation_states), 0)


if __name__ == "__main__":
    unittest.main()
