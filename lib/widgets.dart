import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'models.dart';

class BookingBadge extends StatelessWidget {
  const BookingBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 7 : 8,
      vertical: compact ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          const Icon(
            Icons.event_available_rounded,
            size: 15,
            color: AppColors.warning,
          ),
          const SizedBox(width: 4),
        ],
        const Text(
          'booking',
          style: TextStyle(
            color: AppColors.warning,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class FrequencyWarningBadge extends StatelessWidget {
  const FrequencyWarningBadge({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.notification_important_outlined,
          size: 17,
          color: AppColors.warning,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.warning,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}

Color interestColor(InterestStatus status) => switch (status) {
  InterestStatus.possibly => const Color(0xFF89938B),
  InterestStatus.interested => const Color(0xFFB8730A),
  InterestStatus.confirmed => AppColors.primary,
};

String interestLabel(InterestStatus status) => switch (status) {
  InterestStatus.possibly => 'Possibly',
  InterestStatus.interested => 'Interested',
  InterestStatus.confirmed => 'Confirmed',
};

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {this.size = 8, super.key});

  final InterestStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: interestColor(status),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
    ),
  );
}
