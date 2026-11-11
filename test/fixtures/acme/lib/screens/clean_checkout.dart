import 'package:acme/design_system/app_colors.dart';
import 'package:acme/design_system/app_radius.dart';
import 'package:acme/design_system/app_shadows.dart';
import 'package:acme/design_system/app_spacing.dart';
import 'package:acme/design_system/app_typography.dart';
import 'package:acme/design_system/components.dart';
import 'package:flutter/material.dart';

List<Widget> cleanCheckout() => [
  Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    margin: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.lg,
    ),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.md),
      boxShadow: AppShadows.card,
    ),
    child: const SizedBox(width: AppSpacing.lg, height: AppSpacing.xs),
  ),
  const AppText('Total', style: AppTypography.title),
  const AppText('Pay now', style: AppTypography.body),
  const AppButton(onPressed: null),
  const SizedBox(),
  Container(color: Colors.transparent),
];
