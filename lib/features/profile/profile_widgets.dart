import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/contact_input.dart';
import '../../core/numeric_input.dart';
import '../../core/uploads.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import 'profile_repository.dart';
export '../../core/file_selection.dart' show pickUpload;

class ProfilePanel extends StatelessWidget {
  const ProfilePanel({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(BagooTheme.panelRadius),
      border: Border.all(color: BagooTheme.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x040F172A),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ProfileHeading extends StatelessWidget {
  const ProfileHeading(this.title, this.description, this.icon, {super.key});
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BagooTheme.rose,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExcludeSemantics(
                child: Icon(icon, color: BagooTheme.strong, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.7,
                color: BagooTheme.muted,
              ),
            ),
          ),
        const Divider(height: 32),
      ],
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.user, this.session, {super.key, this.size = 56});
  final Map<String, dynamic> user;
  final WebSession session;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox.square(
      dimension: size,
      child: imageUri(session, user['avatar']) == null
          ? ColoredBox(
              color: BagooTheme.rose,
              child: Center(
                child: Text(
                  (user['name']?.toString().trim().characters.firstOrNull ??
                          'B')
                      .toUpperCase(),
                  style: TextStyle(
                    color: BagooTheme.strong,
                    fontSize: size * .4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : RemoteImage(uri: imageUri(session, user['avatar'])),
    ),
  );
}

String identityLabel(Map<String, dynamic> user) => switch (user['kyc_status']) {
  'approved' || 'verified' => 'Verified Buyer',
  'pending_approval' => 'KYC In Review',
  'rejected' => 'KYC Action Required',
  _ => 'Unverified Account',
};
bool reviewed(Map<String, dynamic> user) =>
    ['approved', 'verified'].contains(user['kyc_status']);

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String description,
  String button,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(description, style: const TextStyle(height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;

abstract class ProfileFormState<T extends StatefulWidget> extends State<T> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? problem, success;
  Map<String, String> errors = {};
  void onFailure(BackendException error) {}

  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) async {
    if (busy || (validate && formKey.currentState?.validate() == false)) {
      return false;
    }
    setState(() {
      busy = true;
      problem = null;
      success = null;
      errors = {};
    });
    try {
      final result = await action();
      if (mounted) setState(() => success = result);
      return true;
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          problem = e.message;
          errors = e.fields;
          onFailure(e);
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(
          () => problem = 'This action could not finish. Check the current details before trying again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String key,
    String label,
    TextEditingController controller, {
    bool required = true,
    bool secret = false,
    bool enabled = true,
    int min = 1,
    int? max,
    int lines = 1,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    String? hint,
    String? Function(String)? check,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      enabled: enabled && !busy,
      obscureText: secret,
      minLines: lines,
      maxLines: secret ? 1 : lines,
      keyboardType: keyboard,
      inputFormatters: keyboard == TextInputType.phone
          ? [mobileNumberFormatter]
          : keyboard == TextInputType.number
          ? [unsignedIntegerFormatter]
          : null,
      autofillHints: autofill,
      maxLength: max,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 5,
        errorText: errors[key],
        errorMaxLines: 5,
        counterText: '',
      ),
      validator: (v) {
        final value = secret ? v ?? '' : v?.trim() ?? '';
        if (required && value.isEmpty) return 'Enter ${label.toLowerCase()}.';
        if (value.isNotEmpty && value.length < min) {
          return 'Use at least $min characters.';
        }
        if (max != null && value.length > max) {
          return 'Use at most $max characters.';
        }
        return check?.call(value) ??
            (keyboard == TextInputType.phone ? mobileNumberValidator(v) : null);
      },
    ),
  );

  Widget content(List<Widget> children) => Form(
    key: formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Notice(
                    [
                      problem!,
                      ...errors.entries.map(
                        (e) => '${e.key.replaceAll('_', ' ')}: ${e.value}',
                      ),
                    ].join('\n'),
                    error: true,
                  ),
                ),
              if (success != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Notice(success!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

abstract class BuyerProfileFormState<T extends StatefulWidget>
    extends ProfileFormState<T>
    with WidgetsBindingObserver {
  ProfileRepository get accountRepository;
  WebPage get accountPage;
  BuyerAccountScope? get parentAccountScope => null;
  late final BuyerAccountScope accountScope;

  bool get hasBuyerAccess =>
      accountScope.isCurrent &&
      identical(accountScope.session, accountRepository.session);

  void clearBuyerDraft();

  @override
  void initState() {
    super.initState();
    accountScope =
        parentAccountScope?.fork() ??
        BuyerAccountScope(accountRepository.session);
    WidgetsBinding.instance.addObserver(this);
    try {
      checkBuyerAccount();
    } on BackendException {
      accountScope.invalidate();
    }
  }

  void checkBuyerAccount({WebPage? result}) {
    if (!identical(accountScope.session, accountRepository.session)) {
      accountScope.invalidate();
    }
    accountScope.check(page: accountPage);
    accountRepository.checked(accountPage);
    if (result != null) {
      accountScope.check(page: result);
      accountRepository.checked(result);
    }
  }

  void _discardBuyer() {
    accountScope.invalidate();
    clearBuyerDraft();
    errors = {};
    success = null;
    problem = null;
  }

  bool ensureBuyerAccess() {
    try {
      checkBuyerAccount();
      return true;
    } on BackendException {
      if (mounted) setState(_discardBuyer);
      return false;
    }
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    try {
      checkBuyerAccount();
    } on BackendException {
      _discardBuyer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ensureBuyerAccess();
  }

  @override
  void onFailure(BackendException error) {
    if (!hasBuyerAccess || [401, 403, 404, 419].contains(error.status)) {
      _discardBuyer();
    }
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (!ensureBuyerAccess()) return Future.value(false);
    return super.perform(() async {
      final result = await action();
      checkBuyerAccount();
      return result;
    }, validate: validate);
  }

  @override
  Widget content(List<Widget> children) => super.content(
    hasBuyerAccess
        ? children
        : [
            const ProfileHeading(
              'Account settings unavailable',
              '',
              Icons.lock_outline,
            ),
            const Notice(
              'Your buyer account changed or access ended. Reopen these settings from your profile.',
              error: true,
            ),
          ],
  );

  @override
  void dispose() {
    accountScope.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class ProfilePagination extends StatelessWidget {
  const ProfilePagination(
    this.page,
    this.onPage, {
    super.key,
    this.disabled = false,
  });
  final Map<String, dynamic> page;
  final ValueChanged<int> onPage;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final current = (page['current_page'] as num?)?.toInt() ?? 1;
    final last = (page['last_page'] as num?)?.toInt() ?? 1;
    if (last <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: disabled || current <= 1
                ? null
                : () => onPage(current - 1),
            child: const Text('Previous'),
          ),
          Text('$current of $last'),
          OutlinedButton(
            onPressed: disabled || current >= last
                ? null
                : () => onPage(current + 1),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class PrivateDocumentPage extends StatefulWidget {
  const PrivateDocumentPage({
    super.key,
    required this.repository,
    required this.path,
    required this.title,
    this.account,
  });
  final ProfileRepository repository;
  final String path, title;
  final BuyerAccountScope? account;
  @override
  State<PrivateDocumentPage> createState() => _PrivateDocumentPageState();
}

class _PrivateDocumentPageState extends State<PrivateDocumentPage>
    with WidgetsBindingObserver {
  late BuyerAccountScope _account;
  Future<RemoteDocument>? _document;
  @override
  void initState() {
    super.initState();
    _account =
        widget.account?.fork() ?? BuyerAccountScope(widget.repository.session);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(PrivateDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository.session, widget.repository.session) ||
        !identical(oldWidget.account, widget.account)) {
      _account.invalidate();
      _account =
          widget.account?.fork() ??
          BuyerAccountScope(widget.repository.session);
      _load();
    } else if (oldWidget.path != widget.path) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_account.isCurrent && mounted) {
      setState(() => _document = null);
    }
  }

  @override
  void dispose() {
    _account.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _load() {
    final account = _account;
    final session = widget.repository.session;
    final path = widget.path;
    if (!account.isCurrent || !identical(account.session, session)) {
      account.invalidate();
      _document = null;
      return;
    }
    _document = () async {
      account.check();
      try {
        final document = await session.documentBytes(path);
        account.check();
        return document;
      } on BackendException catch (e) {
        if ([401, 403, 404, 419].contains(e.status)) account.invalidate();
        rethrow;
      }
    }();
  }

  Widget _failure(String message, {bool retry = true}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Notice(message, error: true),
          TextButton(
            onPressed: retry
                ? () => setState(_load)
                : () => Navigator.of(context).maybePop(),
            child: Text(retry ? 'Try again' : 'Close document'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _account.isCurrent ? widget.title : 'Private document unavailable',
      ),
    ),
    body: SafeArea(
      child: !_account.isCurrent
          ? _failure(
              'Your buyer account changed or access ended. Close this document and reopen it from your account.',
              retry: false,
            )
          : FutureBuilder(
              key: ObjectKey(_document),
              future: _document,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  if (!_account.isCurrent) {
                    return _failure(
                      'Your buyer account changed or access ended. Close this document and reopen it from your account.',
                      retry: false,
                    );
                  }
                  return _failure(
                    snapshot.error is BackendException
                        ? (snapshot.error as BackendException).message
                        : 'The document could not load.',
                  );
                }
                final document = snapshot.data;
                if (document == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return document.mime == 'application/pdf'
                    ? PdfViewer.data(
                        document.bytes,
                        sourceName: widget.title,
                        params: PdfViewerParams(
                          linkHandlerParams: PdfLinkHandlerParams(
                            onLinkTap: (_) {},
                          ),
                        ),
                      )
                    : Center(
                        child: InteractiveViewer(
                          maxScale: 5,
                          child: Image.memory(
                            document.bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Notice(
                              'This image cannot be displayed.',
                              error: true,
                            ),
                          ),
                        ),
                      );
              },
            ),
    ),
  );
}
