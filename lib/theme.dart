import 'package:flutter/material.dart';

/// 따뜻한 톤앤매너 (Modern & Warm) 디자인 토큰.
class AppColors {
  static const background = Color(0xFFFCF8F5); // 우윳빛 오프화이트
  static const surface = Colors.white;
  static const primary = Color(0xFFE2845E); // 따뜻한 코랄
  static const primarySoft = Color(0xFFFFF0ED);
  static const textDark = Color(0xFF2D2522);
  static const textGrey = Color(0xFF786D66);
  static const border = Color(0xFFEFE6E0);
  static const live = Color(0xFF10B981);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      surface: AppColors.background,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textDark,
      elevation: 0.5,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textDark,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textGrey,
        ),
      ),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// 공용 카드 컨테이너 데코레이션.
BoxDecoration cardDecoration({Color? borderColor}) {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: borderColor ?? AppColors.border),
    boxShadow: [
      BoxShadow(
        color: AppColors.textDark.withValues(alpha: 0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
