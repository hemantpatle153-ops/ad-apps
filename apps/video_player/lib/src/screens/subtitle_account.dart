import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../library/online_subtitles.dart';
import '../settings.dart';

const subtitleSignUpUrl = 'https://www.opensubtitles.com/en/users/sign_up';

/// Settings row for the user's own subtitle account, which raises the
/// number of subtitle downloads allowed per day.
class SubtitleAccountTile extends StatelessWidget {
  const SubtitleAccountTile({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final user = settings.subtitleUser;
    if (user != null && settings.subtitleToken != null) {
      return ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const Text('Subtitle account'),
        subtitle: Text('Signed in as $user'),
        trailing: TextButton(
          onPressed: () async {
            await OnlineSubtitles(
                    token: settings.subtitleToken, host: settings.subtitleHost)
                .logout();
            settings.setSubtitleAccount();
          },
          child: const Text('Sign out'),
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.account_circle_outlined),
      title: const Text('Subtitle account'),
      subtitle: const Text('Sign in with a free OpenSubtitles account for '
          'more subtitle downloads per day'),
      enabled: onlineSubtitlesAvailable,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _SignInDialog(settings: settings),
      ),
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.settings});
  final Settings settings;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final user = _user.text.trim();
    if (user.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await OnlineSubtitles().login(user, _password.text);
      widget.settings
          .setSubtitleAccount(user: user, token: login.token, host: login.host);
      if (mounted) Navigator.pop(context);
    } on SubtitleServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No connection. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Subtitle account'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _user,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => openLink(subtitleSignUpUrl),
              child: const Text('Create a free account'),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
      ],
    );
  }
}
