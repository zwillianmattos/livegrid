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
    final label = live ? 'Parar gravação' : 'Gravar';

    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: busy ? null : (live ? onStop : onStart),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.text, width: 3),
            ),
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: live ? 22 : 48,
              height: live ? 22 : 48,
              decoration: BoxDecoration(
                color: busy ? AppColors.textFaint : AppColors.live,
                borderRadius: BorderRadius.circular(live ? 0 : 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
