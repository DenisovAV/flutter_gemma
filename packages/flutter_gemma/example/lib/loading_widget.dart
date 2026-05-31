import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  final String message;
  final int? progress;

  const LoadingWidget({
    required this.message,
    this.progress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: const Alignment(0, 1 / 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
              if (progress != null) ...[
                const SizedBox(height: 8),
                Text('$progress%'),
              ],
            ],
          ),
        );
      },
    );
  }
}
