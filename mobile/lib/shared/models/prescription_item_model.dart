class PrescriptionItemModel {
  const PrescriptionItemModel({
    this.medicationNameAr,
    this.medicationNameEn,
    this.dosage,
    this.frequency,
    this.duration,
    this.quantity,
    this.instructions,
  });

  final String? medicationNameAr;
  final String? medicationNameEn;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? quantity;
  final String? instructions;

  factory PrescriptionItemModel.fromJson(Map<String, dynamic> json) {
    return PrescriptionItemModel(
      medicationNameAr: json['medication_name_ar'] as String?,
      medicationNameEn: json['medication_name_en'] as String?,
      dosage: json['dosage'] as String?,
      frequency: json['frequency'] as String?,
      duration: json['duration'] as String?,
      quantity: json['quantity']?.toString(),
      instructions: json['instructions'] as String?,
    );
  }
}
