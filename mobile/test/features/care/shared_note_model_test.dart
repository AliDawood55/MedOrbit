import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/care/models/shared_note_model.dart';

const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

void main() {
  group('SharedNoteModel.fromJson', () {
    test('parses a fully populated row', () {
      final note = SharedNoteModel.fromJson({
        'id': 'note-1',
        'record_type': 'consultation',
        'chief_complaint': 'Chest pain',
        'diagnosis': 'Angina',
        'treatment_plan': 'Rest and follow-up',
        'clinical_notes': 'Patient responded well.',
        'created_at': '2026-08-01T10:00:00.000Z',
      });

      expect(note.id, 'note-1');
      expect(note.recordType, 'consultation');
      expect(note.chiefComplaint, 'Chest pain');
      expect(note.diagnosis, 'Angina');
      expect(note.treatmentPlan, 'Rest and follow-up');
      expect(note.clinicalNotes, 'Patient responded well.');
      expect(note.createdAt, '2026-08-01T10:00:00.000Z');
    });

    test('missing required id throws FormatException', () {
      expect(
        () => SharedNoteModel.fromJson({'record_type': 'consultation'}),
        throwsFormatException,
      );
    });

    test('optional fields absent parse to null, not fabricated text', () {
      final note = SharedNoteModel.fromJson({'id': 'note-2'});
      expect(note.recordType, isNull);
      expect(note.diagnosis, isNull);
      expect(note.clinicalNotes, isNull);
    });

    test('PRIVACY CANARY: a doctor_notes field in the payload is never read', () {
      final note = SharedNoteModel.fromJson({
        'id': 'note-3',
        'doctor_notes': _canary,
        'clinical_notes': 'Legitimate shared note.',
      });

      // SharedNoteModel has no field for doctor_notes at all, so there is no
      // getter that could ever expose it — assert the only note-carrying
      // field present (clinical_notes) is the legitimate one.
      expect(note.clinicalNotes, 'Legitimate shared note.');
      expect(note.toString(), isNot(contains(_canary)));
    });
  });
}
