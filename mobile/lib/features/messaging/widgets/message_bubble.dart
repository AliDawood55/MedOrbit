import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../models/messaging_models.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.isArabic,
    required this.strings,
    this.onRetry,
    this.onDismiss,
  });

  final CareMessage message;
  final bool isMine;
  final bool isArabic;
  final AppStrings strings;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = message.deliveryState == MessageDeliveryState.failed;
    final pending = message.deliveryState == MessageDeliveryState.sending;
    final background = isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurfaceVariant;
    final time = DateFormat.jm(
      isArabic ? 'ar' : 'en',
    ).format(message.createdAt.toLocal());
    final bodyDirection = Bidi.detectRtlDirectionality(message.body)
        ? ui.TextDirection.rtl
        : ui.TextDirection.ltr;

    return Semantics(
      container: true,
      label:
          '${isMine ? strings.messagesYou : strings.messagesCounterpart}: '
          '${message.body}. $time'
          '${pending ? ', ${strings.messagesSending}' : ''}'
          '${failed ? ', ${strings.messagesSendFailed}' : ''}',
      child: Align(
        alignment: isMine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: failed
                  ? scheme.errorContainer
                  : background.withValues(alpha: pending ? 0.72 : 1),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(AppTheme.radiusLg),
                topEnd: const Radius.circular(AppTheme.radiusLg),
                bottomStart: Radius.circular(
                  isMine ? AppTheme.radiusLg : AppTheme.radiusXs,
                ),
                bottomEnd: Radius.circular(
                  isMine ? AppTheme.radiusXs : AppTheme.radiusLg,
                ),
              ),
              border: failed ? Border.all(color: scheme.error) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMd),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Directionality(
                      textDirection: bodyDirection,
                      child: Text(
                        message.body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: failed ? scheme.onErrorContainer : foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
                    Wrap(
                      spacing: AppTheme.spaceSm,
                      runSpacing: AppTheme.spaceXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: failed
                                    ? scheme.onErrorContainer
                                    : foreground.withValues(alpha: 0.75),
                              ),
                        ),
                        if (pending) ...[
                          SizedBox.square(
                            dimension: AppTheme.iconSm,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          ),
                          Text(
                            strings.messagesSending,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: foreground),
                          ),
                        ],
                        if (failed) ...[
                          Text(
                            strings.messagesSendFailed,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onErrorContainer,
                                  fontWeight: AppTheme.weightBold,
                                ),
                          ),
                          TextButton(
                            onPressed: onRetry,
                            child: Text(strings.retry),
                          ),
                          TextButton(
                            onPressed: onDismiss,
                            child: Text(strings.messagesDismiss),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
