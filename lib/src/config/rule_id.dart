/// A category of design-system values that tokens can describe.
enum DesignCategory {
  /// Colors (`AppColors.primary`).
  color('color'),

  /// Spacing values (`AppSpacing.md`).
  spacing('spacing'),

  /// Corner radii (`AppRadius.md`).
  radius('radius'),

  /// Text styles (`AppTypography.bodyMedium`).
  typography('typography'),

  /// Box shadows (`AppShadows.card`).
  shadow('shadow'),

  /// Icon sizes (`AppIconSize.md`).
  iconSize('icon_size'),

  /// Material elevations (`AppElevation.card`).
  elevation('elevation'),

  /// Replacement widgets (`AppButton` instead of `ElevatedButton`).
  component('component');

  const DesignCategory(this.key);

  /// The configuration key and report label of this category.
  final String key;

  /// Whether this category is described by a class under `tokens:`.
  bool get isToken => this != component;

  /// Looks up a category by its configuration [key].
  static DesignCategory? fromKey(String key) {
    for (final category in values) {
      if (category.key == key) return category;
    }
    return null;
  }
}

/// The rules shipped with this package.
enum RuleId {
  /// Raw color literals and `Colors.*` references.
  avoidRawColor('avoid_raw_color', DesignCategory.color),

  /// Numeric literals used for spacing.
  avoidMagicSpacing('avoid_magic_spacing', DesignCategory.spacing),

  /// Numeric literals used for corner radii.
  avoidRawRadius('avoid_raw_radius', DesignCategory.radius),

  /// Hand-written `TextStyle` constructors.
  avoidInlineTextStyle('avoid_inline_text_style', DesignCategory.typography),

  /// Hand-written `BoxShadow` literals.
  avoidRawShadow('avoid_raw_shadow', DesignCategory.shadow),

  /// Numeric literals used for icon sizes.
  avoidRawIconSize('avoid_raw_icon_size', DesignCategory.iconSize),

  /// Numeric literals used for elevations.
  avoidRawElevation('avoid_raw_elevation', DesignCategory.elevation),

  /// Raw widgets that have a design-system replacement.
  preferDesignSystemComponent(
    'prefer_design_system_component',
    DesignCategory.component,
  );

  const RuleId(this.code, this.category);

  /// Whether the rule can suggest nearest (non-exact) replacements.
  bool get offersNearestFixes =>
      this == avoidRawColor ||
      this == avoidMagicSpacing ||
      this == avoidRawRadius ||
      this == avoidRawIconSize ||
      this == avoidRawElevation;

  /// The diagnostic code, as used in `// ignore:` comments and in reports.
  final String code;

  /// The category this rule enforces.
  final DesignCategory category;

  /// Looks up a rule by its diagnostic [code].
  static RuleId? fromCode(String code) {
    for (final rule in values) {
      if (rule.code == code) return rule;
    }
    return null;
  }
}
