import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

Future<bool> showLeaveDialog(BuildContext context, {required bool refunds}) {
  return _showConfirmDialog(
    context,
    title: refunds
        ? GroupMessages.leaveWithRefundTitle
        : GroupMessages.leaveWithoutRefundTitle,
    body: refunds
        ? GroupMessages.leaveWithRefundBody
        : GroupMessages.leaveWithoutRefundBody,
    confirmLabel: refunds
        ? GroupMessages.leaveWithRefundAction
        : GroupMessages.leaveWithoutRefundAction,
    destructive: !refunds,
  );
}

Future<bool> showDeleteDialog(BuildContext context) {
  return _showConfirmDialog(
    context,
    title: GroupMessages.deleteTitle,
    body: GroupMessages.deleteBody,
    confirmLabel: GroupMessages.deleteAction,
    destructive: true,
  );
}

Future<bool> showRemoveDialog(BuildContext context, {required String name}) {
  return _showConfirmDialog(
    context,
    title: GroupMessages.removeTitle(name),
    body: GroupMessages.removeBody(name),
    confirmLabel: GroupMessages.removeAction,
    destructive: true,
  );
}

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required bool destructive,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body, key: AppKeys.refundWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(GroupMessages.keepSeatAction),
          ),
          FilledButton(
            key: AppKeys.dialogConfirm,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
