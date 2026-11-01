import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Explains the server's existing checkout gate without submitting any data.
Future<bool> showBuyerVerificationPrompt(
  BuildContext context,
  Map<String, dynamic> user,
) async {
  final status = user['kyc_status'];
  final message = status == 'pending_approval'
      ? 'Your ID is awaiting review. Check its status in your account.'
      : user['status'] != 'active' && user['status'] != 'pending_approval'
      ? 'Your account needs attention before checkout. Review your account for next steps.'
      : 'Verify your identity before checkout. Review your account and submit a valid ID.';
  FocusManager.instance.primaryFocus?.unfocus();
  return await showDialog<bool>(
        context: context,
        builder: (context) {
          final media = MediaQuery.of(context);
          final compact = media.size.height - media.viewInsets.bottom < 360;
          return AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            icon: compact
                ? null
                : const Icon(
                    Icons.verified_user_outlined,
                    color: BagooTheme.strong,
                    size: 32,
                  ),
            titlePadding: EdgeInsets.fromLTRB(24, compact ? 16 : 0, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 8 : 16),
            title: const Text(
              'Verification needed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            content: Text(
              message,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep browsing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Review account'),
              ),
            ],
          );
        },
      ) ??
      false;
}
