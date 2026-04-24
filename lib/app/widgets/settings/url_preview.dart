import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class UrlPreview extends StatelessWidget {
  const UrlPreview({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: AppTheme.label(size: 10)),
        ),
        Expanded(
          child: Text(
            url,
            style: AppTheme.numeric(
              size: 11,
              color: AppColors.textMuted,
              weight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
