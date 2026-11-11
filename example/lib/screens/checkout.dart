import 'package:acme_shop/design_system/app_button.dart';
import 'package:acme_shop/design_system/app_colors.dart';
import 'package:acme_shop/design_system/app_radius.dart';
import 'package:acme_shop/design_system/app_shadows.dart';
import 'package:acme_shop/design_system/app_spacing.dart';
import 'package:acme_shop/design_system/app_text.dart';
import 'package:acme_shop/design_system/app_typography.dart';
import 'package:flutter/material.dart';

/// The checkout screen, written against the design system.
class Checkout extends StatelessWidget {
  const Checkout({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText('Order summary', style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          AppText(
            'Free delivery on orders over \$50',
            style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppText('Total: \$64.00'),
          const SizedBox(height: AppSpacing.lg),
          AppButton(onPressed: () {}, child: const AppText('Pay now')),
        ],
      ),
    );
  }
}
