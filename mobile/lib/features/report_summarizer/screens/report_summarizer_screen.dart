import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/platform/report_file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/report_summarizer_provider.dart';
import '../widgets/report_summary_result_card.dart';

class ReportSummarizerScreen extends ConsumerStatefulWidget {
  const ReportSummarizerScreen({super.key});

  @override
  ConsumerState<ReportSummarizerScreen> createState() =>
      _ReportSummarizerScreenState();
}

class _ReportSummarizerScreenState
    extends ConsumerState<ReportSummarizerScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _summarizeAnother() {
    ref.read(reportSummarizerControllerProvider.notifier).reset();
    _controller.clear();
  }

  /// Picking itself never reaches the API — the notifier only ever sees a
  /// path/name/size, so this method never touches network code, and a
  /// cancelled picker (a null result) is silent, matching the avatar-upload
  /// precedent in Profile. `ReportFilePicker` throws (including
  /// `MissingPluginException` when no native implementation is registered,
  /// e.g. under `flutter_test` or on a platform without one yet) rather than
  /// returning an error value, so any failure funnels through the catch.
  Future<void> _pickFile() async {
    final notifier = ref.read(reportSummarizerControllerProvider.notifier);
    PickedReportFile? picked;
    try {
      picked = await ReportFilePicker.pickReportFile();
    } catch (_) {
      notifier.reportPickFailure();
      return;
    }
    if (picked == null) return;
    notifier.selectFile(
      filePath: picked.path,
      fileName: picked.name,
      fileSizeBytes: picked.sizeBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(reportSummarizerControllerProvider);
    final notifier = ref.read(reportSummarizerControllerProvider.notifier);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.reportSummarizerTitle)),
      useSafeArea: true,
      keyboardAware: true,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
        children: [
          ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageIntro(
                  title: strings.reportSummarizerTitle,
                  subtitle: strings.reportSummarizerSubtitle,
                  icon: Icons.summarize_outlined,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                InlineMessage(
                  message: strings.reportSummaryDisclaimer,
                  tone: InlineMessageTone.warning,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                if (state.error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: ErrorRetryState(
                        title: strings.reportSummarizerLoadError,
                        message: _errorMessage(strings, state.error!),
                        retryLabel: strings.retry,
                        onRetry: notifier.retry,
                        variant: ErrorRetryVariant.compact,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                ],
                if (state.result != null)
                  ReportSummaryResultCard(
                    result: state.result!,
                    strings: strings,
                    onSummarizeAnother: _summarizeAnother,
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionHeader(title: strings.reportInputLabel),
                          Text(
                            strings.pasteOrUploadReport,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          if (state.hasSelectedFile)
                            _SelectedFileRow(
                              fileName: state.selectedFileName!,
                              strings: strings,
                              onRemove: notifier.clearSelectedFile,
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickFile,
                                  icon: const Icon(Icons.upload_file_outlined),
                                  label: Text(strings.uploadReportFile),
                                ),
                                const SizedBox(height: AppTheme.spaceXs),
                                Text(
                                  strings.supportedReportFiles,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          if (state.fileError != null) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            InlineMessage(
                              message: _fileErrorMessage(strings, state.fileError!),
                              tone: InlineMessageTone.error,
                            ),
                          ],
                          const SizedBox(height: AppTheme.spaceLg),
                          AppTextField(
                            label: strings.reportInputLabel,
                            hintText: strings.reportInputHint,
                            controller: _controller,
                            enabled: !state.hasSelectedFile,
                            keyboardType: TextInputType.multiline,
                            minLines: 6,
                            maxLines: 12,
                            onChanged: notifier.updateInput,
                          ),
                          if (state.showValidationError) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            InlineMessage(
                              message: strings.reportSummaryEmptyError,
                              tone: InlineMessageTone.error,
                            ),
                          ],
                          const SizedBox(height: AppTheme.spaceLg),
                          PrimaryButton(
                            label: state.hasSelectedFile
                                ? strings.summarizeUploadedReport
                                : strings.summarizeReport,
                            isLoading: state.isLoading,
                            onPressed: notifier.submit,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedFileRow extends StatelessWidget {
  const _SelectedFileRow({
    required this.fileName,
    required this.strings,
    required this.onRemove,
  });

  final String fileName;
  final AppStrings strings;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceMd,
        vertical: AppTheme.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: colorScheme.primary),
          const SizedBox(width: AppTheme.spaceSm),
          Expanded(
            child: Text(
              strings.selectedReportFile(fileName),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const ValueKey('report-remove-file'),
            onPressed: onRemove,
            child: Text(strings.removeSelectedFile),
          ),
        ],
      ),
    );
  }
}

String _errorMessage(AppStrings strings, ReportSummarizerErrorKind kind) {
  return switch (kind) {
    ReportSummarizerErrorKind.timeout => strings.reportSummarizerTimeoutError,
    ReportSummarizerErrorKind.serviceUnavailable =>
      strings.reportSummarizerServiceUnavailableError,
    ReportSummarizerErrorKind.generic => strings.reportSummaryGenericError,
  };
}

String _fileErrorMessage(AppStrings strings, ReportFileErrorKind kind) {
  return switch (kind) {
    ReportFileErrorKind.unsupportedType => strings.unsupportedReportFile,
    ReportFileErrorKind.tooLarge => strings.reportFileTooLarge,
    ReportFileErrorKind.pickFailed => strings.reportFilePickFailed,
  };
}
