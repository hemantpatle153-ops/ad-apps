import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../logic/report.dart';
import 'scope.dart';

Future<void> showReportSheet(BuildContext context, String postId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AppScope(
        controller: AppScope.read(context),
        child: ReportSheet(postId: postId),
      ),
    );

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.postId});
  final String postId;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.read(context);
    final s = app.s;
    final reason = _reason;
    if (reason == null) return;
    final draft = ReportDraft(item: widget.postId, reason: reason, note: _note.text);
    final problem = draft.problem;
    if (problem != null) {
      setState(() => _error = switch (problem) {
            ReportProblem.noteNeeded => s.t(L.reportNoteRequired),
            ReportProblem.noteTooLong => s.t(L.reportNoteTooLong, {'n': maxReportNote}),
            ReportProblem.badItem => s.t(L.reportFailed),
          });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final outcome = await app.report(draft);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (outcome) {
      case ReportOutcome.sent:
        Navigator.of(context).pop();
        context.toast(s.t(L.reportSent));
      case ReportOutcome.duplicate:
        setState(() => _error = s.t(L.reportDuplicate));
      case ReportOutcome.rateLimited:
        setState(() => _error = s.t(L.reportLimit));
      case ReportOutcome.failed || ReportOutcome.invalid:
        setState(() => _error = s.t(L.reportFailed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t(L.reportMistake),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text(s.t(L.reportPickReason), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ReportReason.values)
                  ChoiceChip(
                    label: Text(s.reportReason(r)),
                    selected: _reason == r,
                    onSelected: (_) => setState(() {
                      _reason = r;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: maxReportNote,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: s.t(L.reportNoteHint),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
              ),
            Text(s.t(L.reportPrivacy), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _reason == null || _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(s.t(L.reportSend)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
