import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

bool _stackForWidth(
  BuildContext context,
  double width, {
  double threshold = AppTheme.compactBreakpoint,
}) {
  final scaledBody = MediaQuery.textScalerOf(context).scale(AppTheme.fontMd);
  return width < threshold || scaledBody >= AppTheme.fontLg * 1.2;
}

/// Centers page content and applies MedOrbit's 12/16/24 responsive gutters.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = AppTheme.maxPhoneContentWidth,
    this.padding,
    this.alignment = AlignmentDirectional.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding ?? EdgeInsetsDirectional.symmetric(
                horizontal: AppTheme.pageHorizontalPadding(width),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

enum InlineMessageTone { info, success, warning, error }

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.message,
    this.tone = InlineMessageTone.info,
  });

  final String message;
  final InlineMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      InlineMessageTone.success => (AppTheme.success, Icons.check_circle_outline_rounded),
      InlineMessageTone.warning => (AppTheme.warning, Icons.warning_amber_rounded),
      InlineMessageTone.error => (Theme.of(context).colorScheme.error, Icons.error_outline_rounded),
      InlineMessageTone.info => (AppTheme.info, Icons.info_outline_rounded),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: AppTheme.iconMd),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppTheme.spaceMd),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightBold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            subtitle!,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shouldStack = trailing != null && _stackForWidth(context, constraints.maxWidth);
          if (shouldStack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: AppTheme.spaceSm),
                Align(alignment: AlignmentDirectional.centerStart, child: trailing!),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              if (trailing != null) ...[
                const SizedBox(width: AppTheme.spaceSm),
                Flexible(child: trailing!),
              ],
            ],
          );
        },
      ),
    );
  }
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
    this.color,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    Widget iconBox() => Container(
          width: AppTheme.minTouchTarget,
          height: AppTheme.minTouchTarget,
          decoration: BoxDecoration(
            gradient: color == null ? AppTheme.primaryGradient : null,
            color: color == null ? null : accent,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: AppTheme.shadowSmOf(context),
          ),
          child: Icon(icon!, color: Colors.white, size: AppTheme.iconLg),
        );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightExtraBold),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shouldStack = _stackForWidth(context, constraints.maxWidth);
            if (shouldStack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[
                    Align(alignment: AlignmentDirectional.centerStart, child: iconBox()),
                    const SizedBox(height: AppTheme.spaceMd),
                  ],
                  copy,
                  if (trailing != null) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    Align(alignment: AlignmentDirectional.centerStart, child: trailing!),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  iconBox(),
                  const SizedBox(width: AppTheme.spaceMd),
                ],
                Expanded(child: copy),
                if (trailing != null) ...[
                  const SizedBox(width: AppTheme.spaceSm),
                  Flexible(child: trailing!),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final iconBox = icon == null
        ? null
        : Container(
            width: AppTheme.minTouchTarget,
            height: AppTheme.minTouchTarget,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(icon!, color: accent, size: AppTheme.iconMd),
          );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightBold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticLabel,
      container: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shouldStack = trailing != null && _stackForWidth(context, constraints.maxWidth);
                  if (shouldStack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (iconBox != null) ...[
                              iconBox,
                              const SizedBox(width: AppTheme.spaceMd),
                            ],
                            Expanded(child: copy),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        Align(alignment: AlignmentDirectional.centerStart, child: trailing!),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (iconBox != null) ...[
                        iconBox,
                        const SizedBox(width: AppTheme.spaceMd),
                      ],
                      Expanded(child: copy),
                      if (trailing != null) ...[
                        const SizedBox(width: AppTheme.spaceSm),
                        Flexible(child: trailing!),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    return Semantics(
      button: onTap != null,
      value: value,
      label: label,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Icon(icon!, color: accent, size: AppTheme.iconMd),
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightExtraBold),
                      ),
                      const SizedBox(height: AppTheme.spaceXs),
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
