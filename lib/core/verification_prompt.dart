import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Explains the server's existing checkout gate without submitting any data.
Future<bool> showBuyerVerificationPrompt(
  BuildContext context,
  Map<String, dynamic> user,
) async {
  final status = user['kyc_status'];
  final message = status == 'pending_approval'
      ? 'Your identity information is awaiting review. You can check its status in your account.'
      : user['status'] != 'active' && user['status'] != 'pending_approval'
      ? 'Your account needs attention before checkout. Review your account details for the next step.'
      : 'Complete your identity verification before checkout. You can review your information and submit a valid ID from your account.';
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(
            Icons.verified_user_outlined,
            color: BagooTheme.strong,
            size: 32,
          ),
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
        ),
      ) ??
      false;
}
