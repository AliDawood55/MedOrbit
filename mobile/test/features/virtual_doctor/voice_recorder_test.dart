import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/virtual_doctor/providers/virtual_doctor_provider.dart';
void main() { test('recording-cap state defaults to absent outside recording', () { expect(const VirtualDoctorState().recordingRemainingSeconds, isNull); }); }
