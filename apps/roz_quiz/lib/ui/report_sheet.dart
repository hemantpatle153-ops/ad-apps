import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/report.dart';
import '../l10n/strings.dart';
import 'scope.dart';

Future<void> showReportSheet(BuildContext context, Question question) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ReportSheet(question: question),
    );

T reportProblemText(ReportProblem p) => switch (p) {
      ReportProblem.missingItem => T.reportMissingItem,
      ReportProblem.noteTooLong => T.reportNoteTooLong,
      ReportProblem.noteRequired => T.reportNoteRequired,
      ReportProblem.tooSoon => T.reportTooSoon,
      ReportProblem.dailyLimit => T.reportDailyLimit,
      ReportProblem.alreadyReported => T.reportAlready,
    };

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.question});
  final Question question;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason _reason = ReportReason.wrongAnswer;
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
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await app.sendReport(item: widget.question.id, reason: _reason, note: _note.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(s.t(T.reportThanks))));
    } on ReportException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = s.t(e.problem == null ? T.reportOffline : reportProblemText(e.problem!));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final app = context.app;
    final blocked = app.reports.precheck(widget.question.id);
    final reasons = {
      ReportReason.wrongAnswer: T.reasonWrongAnswer,
      ReportReason.wrongQuestion: T.reasonWrongQuestion,
      ReportReason.translation: T.reasonTranslation,
      ReportReason.other: T.reasonOther,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t(T.reportTitle),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.question.q.of(app.lang),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (blocked == ReportProblem.alreadyReported) ...[
              Text(s.t(T.reportAlready)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(), child: Text(s.t(T.close))),
            ] else ...[
              Text(s.t(T.reportReasonLabel),
                  style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v ?? _reason),
                child: Column(children: [
                  for (final e in reasons.entries)
                    RadioListTile<ReportReason>(
                      value: e.key,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t(e.value)),
                    ),
                ]),
              ),
              TextField(
                controller: _note,
                maxLength: kReportNoteMax,
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: s.t(T.reportNoteHint),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(s.t(T.send)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
