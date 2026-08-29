import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/admin_doctor_application.dart';

/// Localized label and tone for an application lifecycle state. An
/// unrecognized status keeps its raw server value and a neutral tone rather
/// than being presented as one of the four known outcomes.
(String, Color) adminApplicationStatusVisual(
  AdminDoctorApplication application,
  AppStrings strings,
) => switch (application.status) {
  AdminApplicationStatus.pending => (
    strings.adminApplicationsStatusPending,
    AppTheme.warning,
  ),
  AdminApplicationStatus.approved => (
    strings.adminApplicationsStatusApproved,
    AppTheme.success,
  ),
  AdminApplicationStatus.rejected => (
    strings.adminApplicationsStatusRejected,
    AppTheme.danger,
  ),
  AdminApplicationStatus.withdrawn => (
    strings.adminApplicationsStatusWithdrawn,
    AppTheme.info,
  ),
  AdminApplicationStatus.unknown => (application.statusValue, AppTheme.primary),
};
