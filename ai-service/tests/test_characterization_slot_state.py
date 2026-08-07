"""
Characterization tests for SlotFiller.conversation_states growth/collision behavior.

These tests pin the CURRENT (pre-fix) behavior of chatbot/nlu/slots.py, in
particular how chatbot/main.py keys conversation_states via str(hash(message))
rather than a real session/conversation identifier. They exist to protect
against silent behavior changes while a bounded/keyed-by-session fix is
designed, not to assert the current behavior is correct.
"""
import unittest

from chatbot.nlu.slots import SlotFiller


class TestSlotFillerStateKeying(unittest.TestCase):
    """Pins how conversation_states is keyed, per main.py's str(hash(message)) pattern."""

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

    def test_many_unique_messages_grow_state_without_bound(self):
        """
        There is no eviction/TTL/LRU mechanism: conversation_states grows by
        exactly one entry per unique message, forever, for as long as the
        SlotFiller instance lives.
        """
        num_messages = 500
        for i in range(num_messages):
            message = f"unique message number {i}"
            key = str(hash(message))
            self.slots.update_state(key, "find_doctor", {"specialty": "cardiology"})

        self.assertEqual(len(self.slots.conversation_states), num_messages)

    def test_clear_state_removes_single_entry_only(self):
        self.slots.update_state("key-a", "find_doctor", {"specialty": "cardiology"})
        self.slots.update_state("key-b", "find_doctor", {"specialty": "dermatology"})

        self.slots.clear_state("key-a")

        self.assertNotIn("key-a", self.slots.conversation_states)
        self.assertIn("key-b", self.slots.conversation_states)

    def test_clear_state_is_the_only_existing_eviction_mechanism(self):
        """
        clear_state() exists and works, but nothing in SlotFiller or in
        chatbot/main.py's call site currently invokes it automatically --
        confirmed by inspection (main.py never calls slot_filler.clear_state).
        This test only pins that clear_state itself functions correctly;
        it does not assert that anything calls it in production.
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
