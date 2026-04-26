import 'package:flutter/material.dart';

import '../../models/session_state.dart';
import '../../theme/app_theme.dart';

class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final SessionState state;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final busy =
        state == SessionState.starting || state == SessionState.stopping;
    final live = state == SessionState.live || state == SessionState.degraded;

    return GestureDetector(
      onTap: busy ? null : (live ? onStop : onStart),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: live ? 22 : 52,
          height: live ? 22 : 52,
          decoration: BoxDecoration(
            color: busy ? AppColors.textFaint : AppColors.live,
            borderRadius: BorderRadius.circular(live ? 4 : 999),
            boxShadow: live
                ? [
                    BoxShadow(
                      color: AppColors.live.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}
