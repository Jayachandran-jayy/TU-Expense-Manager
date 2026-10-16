/// Settings: categorization, cleanup, data and updates.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/aliases.dart';
import '../../core/backup_data.dart';
import '../../core/backup_validate.dart';
import '../../core/constants.dart';
import '../../core/ledger_prefs.dart';
import '../../ui_shared/loading_dialog.dart';
import '../../ui_shared/theme_controller.dart';
import '../../ui_shared/theme_models.dart';
import '../auto_sync.dart';
import '../backup_dialogs.dart';
import '../backup_files.dart';
import '../connection_monitor.dart';
import '../database.dart';
import '../services/app_lock_service.dart';
import '../services/local_llm_service.dart';
import '../sync_client.dart';
import '../sync_prefs.dart';
import '../update_service.dart';
import '../../core/parser.dart';
import '../sms_source.dart';
import '../widgets/paste_transaction_dialog.dart';
import '../widgets/server_backups_sheet.dart';
import '../../ui_shared/shared_controls.dart';
import 'contribute_sample_dialog.dart';
import '../services/github_contribution_helper.dart';
import 'categories_screen.dart';
import 'merchant_defaults_screen.dart';
import 'merge_names_screen.dart';
import 'scan_review_screen.dart';
import 'update_dialog.dart';

/// The second destination. A body only — the shell it sits in supplies the
/// Scaffold and the app bar, so there is no second one of either here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onChanged});

  /// Called when something here changed the ledger.
  ///
  /// A sync applies edits made in a browser, so this screen can now write to the
  /// database. The shell reloads on leaving Settings anyway, but relying on that
  /// alone would leave stale rows visible if the user syncs and then navigates
  /// somewhere else first. The pushed sub-screens already take this callback for
  /// the same reason.
  final VoidCallback? onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DateFormat _checkedFormat = DateFormat('d MMM yyyy, h:mm a');

  bool _autoCheck = false;
  bool _isFdroidPresent = false;
  String _version = '';
  String _build = '';
  DateTime? _lastChecked;
  bool _loading = true;
  bool _checking = false;
  bool _appLock = false;
  bool _trackReceived = false;
  bool _aiFallback = false;
  bool _isAiModelAvailable = false;
  int? _aiModelSizeBytes;
  double? _downloadProgress;
  bool _isAiDownloading = false;

  /// One at a time, and neither while the other runs: both walk the whole
  /// database, and a restore landing halfway through an export would write a
  /// workbook of two different ledgers.
  bool _exporting = false;
  bool _restoring = false;

  /// A sync walks the whole database too, so it joins the same queue.
  bool _syncing = false;

  bool get _busyWithData => _exporting || _restoring || _syncing;

  // Server sync, all read in _load().
  Uri? _serverUrl;
  String? _syncUser;
  String _deviceLabel = '';
  DateTime? _lastPushed;
  String? _syncStatus;
  bool _autoAfterScan = false;
  bool _auto = true;
  int _autoMinutes = kDefaultAutoSyncMinutes;

  /// The release a check on this screen turned up, kept so the Install button
  /// survives dismissing the dialog.
  AppRelease? _available;

  /// The outcome of the last manual check, in one line. Null before anything
  /// has been asked for, and while an update is being offered instead.
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final auto = await UpdatePrefs.instance.autoCheckEnabled();
    final last = await UpdatePrefs.instance.lastChecked();
    final isFdroidClient = await isFdroidClientInstalled();
    final isFdroidInstaller = isFdroidStore(info.installerStore);

    const SyncPrefs sync = SyncPrefs.instance;
    final Uri? serverUrl = await sync.baseUrl();
    final String? syncUser = await sync.username();
    final String deviceLabel = await sync.deviceLabel();
    final DateTime? lastPushed = await sync.lastPushed();
    final String? lastResult = await sync.lastResult();
    final bool autoAfterScan = await sync.autoAfterScan();
    final bool autoSync = await sync.auto();
    final int autoMinutes = await sync.autoMinutes();
    final bool appLock = await LedgerPrefs.instance.appLockEnabled();
    final bool trackReceived = await LedgerPrefs.instance.trackReceived();
    final bool aiFallback = await LedgerPrefs.instance.aiFallbackEnabled();
    final bool isAiAvailable = await LocalLlmService.instance.isModelAvailable();
    final int? aiSizeBytes = await LocalLlmService.instance.getModelSizeBytes();

    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
      _autoCheck = auto;
      _lastChecked = last;
      _isFdroidPresent = isFdroidClient || isFdroidInstaller;
      _serverUrl = serverUrl;
      _syncUser = syncUser;
      _deviceLabel = deviceLabel;
      _lastPushed = lastPushed;
      _syncStatus = lastResult;
      _autoAfterScan = autoAfterScan;
      _auto = autoSync;
      _autoMinutes = autoMinutes;
      _appLock = appLock;
      _trackReceived = trackReceived;
      _aiFallback = aiFallback;
      _isAiModelAvailable = isAiAvailable;
      _aiModelSizeBytes = aiSizeBytes;
      _loading = false;
    });
  }

  Future<void> _setAppLock(bool value) async {
    if (value) {
      final bool canAuth = await AppLockService.instance.canAuthenticate();
      if (!canAuth) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometrics or device screen lock (PIN/pattern) is not set up on this device.',
            ),
          ),
        );
        return;
      }
      final bool success = await AppLockService.instance.authenticate(
        localizedReason:
            'Authenticate with biometrics or screen lock to enable App Lock.',
      );
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication cancelled or failed.')),
        );
        return;
      }
      setState(() => _appLock = true);
      await LedgerPrefs.instance.setAppLockEnabled(true);
      await AppLockService.instance.updateSecureFlag(true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App Lock enabled.')),
      );
    } else {
      final bool success = await AppLockService.instance.authenticate(
        localizedReason: 'Authenticate to disable App Lock.',
      );
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required to disable App Lock.'),
          ),
        );
        return;
      }
      setState(() => _appLock = false);
      await LedgerPrefs.instance.setAppLockEnabled(false);
      await AppLockService.instance.updateSecureFlag(false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App Lock disabled.')),
      );
    }
  }

  Future<void> _setTrackReceived(bool value) async {
    setState(() => _trackReceived = value);
    await LedgerPrefs.instance.setTrackReceived(value);
    widget.onChanged?.call();
  }

  Future<void> _setAiFallback(bool value) async {
    if (value && !_isAiModelAvailable) {
      _showDownloadModelDialog();
      return;
    }
    setState(() => _aiFallback = value);
    await LedgerPrefs.instance.setAiFallbackEnabled(value);
  }

  void _showDownloadModelDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download AI Model?'),
        content: const Text(
          'To use on-device AI parsing, download the lightweight Qwen 2.5 (0.5B) model (~397 MB).\n\n'
          'The model runs 100% locally and offline on your device CPU. No internet is used during parsing, and you can delete it at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startModelDownload();
            },
            child: const Text('Download Now'),
          ),
        ],
      ),
    );
  }

  void _startModelDownload() {
    setState(() {
      _isAiDownloading = true;
      _downloadProgress = 0.0;
    });
    LocalLlmService.instance.downloadDefaultModel().listen(
      (progress) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress);
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isAiDownloading = false;
          _downloadProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $err')),
        );
      },
      onDone: () async {
        if (!mounted) return;
        final bool available = await LocalLlmService.instance.isModelAvailable();
        final int? size = await LocalLlmService.instance.getModelSizeBytes();
        if (!mounted) return;
        setState(() {
          _isAiDownloading = false;
          _downloadProgress = null;
          _isAiModelAvailable = available;
          _aiModelSizeBytes = size;
          _aiFallback = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI model downloaded and ready!')),
        );
      },
      cancelOnError: true,
    );
  }

  Future<void> _pickLocalModel() async {
    final bool success = await LocalLlmService.instance.pickCustomModel();
    if (!mounted) return;
    if (success) {
      final bool available = await LocalLlmService.instance.isModelAvailable();
      final int? size = await LocalLlmService.instance.getModelSizeBytes();
      if (!mounted) return;
      setState(() {
        _isAiModelAvailable = available;
        _aiModelSizeBytes = size;
        _aiFallback = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom model loaded and activated!')),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid .gguf model selected.')),
      );
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete AI Model?'),
        content: const Text('This will delete the local AI model file and free up device storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await LocalLlmService.instance.deleteDefaultModel();
      await LedgerPrefs.instance.setAiFallbackEnabled(false);
      setState(() {
        _isAiModelAvailable = false;
        _aiModelSizeBytes = null;
        _aiFallback = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI model deleted.')),
        );
      }
    }
  }

  Future<void> _openPasteTransaction() async {
    await showPasteTransactionDialog(
      context,
      database: AppDatabase.instance,
      onTransactionAdded: widget.onChanged,
    );
  }

  Future<void> _scanExistingSmsForReview() async {
    final bool aiAvailable =
        await LocalLlmService.instance.isModelAvailable();
    if (!mounted) return;

    final candidates = <CandidateTransaction>[];
    final db = AppDatabase.instance;
    final sms = SmsSource();

    await withLoadingModal<void>(
      context: context,
      message: 'Scanning SMS for transactions…',
      subtitle: aiAvailable
          ? 'Evaluating via patterns & on-device AI'
          : 'Evaluating via patterns',
      task: () async {
        final seenKeys = <String>{};

        // 1. Gather unadded SMS
        final unaddedList = await db.unaddedSms();
        for (final msg in unaddedList) {
          ParsedSms? parsed =
              SmsParser.parse(msg.body, receivedAt: msg.receivedAt);
          if (parsed == null && aiAvailable) {
            try {
              parsed = await LocalLlmService.instance.parseSms(
                msg.body,
                receivedAt: msg.receivedAt,
              );
            } catch (_) {}
          }
          if (parsed != null) {
            final isDup = await db.isDuplicateOrDeleted(parsed);
            final key =
                '${parsed.amount}|${parsed.merchant.toLowerCase()}|${parsed.date.millisecondsSinceEpoch}|${parsed.direction.name}|${parsed.reference}';
            if (!isDup && !seenKeys.contains(key)) {
              seenKeys.add(key);
              candidates.add(
                CandidateTransaction(
                  parsed: parsed,
                  rawBody: msg.body,
                  unaddedSmsId: msg.id,
                  selected: true,
                ),
              );
            }
          }
        }

        // 2. Gather telephony inbox if supported
        if (sms.isSupported) {
          final hasPerm = await sms.requestPermission();
          if (hasPerm) {
            final inbox = await sms.readInbox();
            for (final msg in inbox) {
              ParsedSms? parsed =
                  SmsParser.parse(msg.body, receivedAt: msg.receivedAt);
              if (parsed == null && aiAvailable) {
                try {
                  parsed = await LocalLlmService.instance.parseSms(
                    msg.body,
                    receivedAt: msg.receivedAt,
                  );
                } catch (_) {}
              }
              if (parsed != null) {
                final isDup = await db.isDuplicateOrDeleted(parsed);
                final key =
                    '${parsed.amount}|${parsed.merchant.toLowerCase()}|${parsed.date.millisecondsSinceEpoch}|${parsed.direction.name}|${parsed.reference}';
                if (!isDup && !seenKeys.contains(key)) {
                  seenKeys.add(key);
                  candidates.add(
                    CandidateTransaction(
                      parsed: parsed,
                      rawBody: msg.body,
                      selected: true,
                    ),
                  );
                }
              }
            }
          }
        }
      },
    );

    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No new transactions found in existing SMS.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => ScanReviewScreen(
          candidates: candidates,
          database: db,
          onAdded: widget.onChanged,
        ),
      ),
    );
  }

  Future<void> _setAutoCheck(bool value) async {
    // Optimistic: the switch is the only writer, so there is nothing to lose a
    // race against and no reason to make it lag a disk write.
    setState(() => _autoCheck = value);
    await UpdatePrefs.instance.setAutoCheckEnabled(value);
  }

  /// Asks for the server address.
  Future<void> _editServerUrl() async {
    final String? entered = await _askForText(
      title: 'Server address',
      hint: 'http://192.168.1.99:8099',
      initial: _serverUrl?.toString() ?? 'http://',
      keyboardType: TextInputType.url,
      validate: SyncPrefs.baseUrlProblem,
    );
    if (entered == null) return;

    await SyncPrefs.instance.setBaseUrl(entered);
    if (!mounted) return;
    setState(() => _serverUrl = Uri.tryParse(entered.trim()));
  }

  /// Asks what to call this device in the browser's picker.
  Future<void> _editDeviceLabel() async {
    final String? entered = await _askForText(
      title: 'Name for this device',
      hint: "Jay's Pixel",
      initial: _deviceLabel,
      validate: (String value) =>
          value.trim().isEmpty ? 'Give this device a name.' : null,
    );
    if (entered == null) return;

    await SyncPrefs.instance.setDeviceLabel(entered);
    if (!mounted) return;
    setState(() => _deviceLabel = entered.trim());
  }

  /// Checks the server is there, without needing an account.
  ///
  /// Separate from signing in so a wrong address and a wrong password are
  /// distinguishable, which is most of what makes setting this up bearable.
  Future<void> _testConnection() async {
    final Uri? base = _serverUrl;
    if (base == null) {
      _say('Add the server address first.');
      return;
    }
    setState(() => _syncing = true);
    try {
      final SyncOutcome result = await withLoadingModal<SyncOutcome>(
        context: context,
        message: 'Testing connection…',
        subtitle: 'Checking server address…',
        task: () => SyncClient.instance.testConnection(base),
      );
      // Whatever this found is what the light should be showing, immediately —
      // testing the connection is the one action whose whole purpose is to
      // answer that question.
      unawaited(ConnectionMonitor.instance.check(force: true));
      if (!mounted) return;
      setState(() => _syncStatus =
          result.failed ? result.error : 'The server answered. Sign in next.');
      _say(result.failed ? result.error! : 'The server is there.');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Signs in, or out.
  Future<void> _signIn() async {
    final Uri? base = _serverUrl;
    if (base == null) {
      _say('Add the server address first.');
      return;
    }

    final (String, String)? credentials = await _askForCredentials();
    if (credentials == null || !mounted) return;

    setState(() => _syncing = true);
    try {
      final SyncOutcome result = await withLoadingModal<SyncOutcome>(
        context: context,
        message: 'Signing in…',
        subtitle: 'Authenticating with server…',
        task: () => SyncClient.instance.signIn(
          base: base,
          username: credentials.$1,
          password: credentials.$2,
        ),
      );
      if (!mounted) return;
      if (result.failed) {
        setState(() => _syncStatus = result.error);
        _say(result.error!);
        return;
      }
      final String? user = await SyncPrefs.instance.username();
      if (!mounted) return;
      setState(() {
        _syncUser = user;
        _syncStatus = _auto
            ? 'Signed in. Syncing now, and automatically from here on.'
            : 'Signed in. Tap Sync now to upload.';
      });
      _say('Signed in as $user.');
      // Signing in is the moment sync becomes possible, and the timer was armed
      // before there was a session for it to use. Not awaited: the first upload
      // is a whole ledger, and nothing on this screen should wait for it.
      if (_auto) unawaited(AutoSync.instance.resume());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _syncing = true);
    try {
      await withLoadingModal<void>(
        context: context,
        message: 'Signing out…',
        task: SyncClient.instance.signOut,
      );
      if (!mounted) return;
      setState(() {
        _syncUser = null;
        _syncStatus = 'Signed out.';
      });
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Drains the edit queue, applies it, and uploads the ledger.
  Future<void> _syncNow() async {
    if (_busyWithData) return;
    setState(() => _syncing = true);
    try {
      final SyncOutcome result = await withLoadingModal<SyncOutcome>(
        context: context,
        message: 'Syncing with server…',
        subtitle: 'Uploading ledger and applying edits…',
        task: () => SyncClient.instance.syncNow(
          // A sync can apply edits made in a browser, so the shell has to know the
          // ledger moved underneath it.
          onChanged: widget.onChanged,
        ),
      );
      // The light in the app bar is looking at the same server this just spoke
      // to, and a manual sync is the strongest evidence there is about it.
      ConnectionMonitor.instance.record(result);
      if (!mounted) return;
      final DateTime? pushed = await SyncPrefs.instance.lastPushed();
      if (!mounted) return;
      setState(() {
        _syncStatus = result.describe();
        _lastPushed = pushed;
        if (result.signedOut) _syncUser = null;
      });
      _say(result.describe());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _setAutoAfterScan(bool value) async {
    setState(() => _autoAfterScan = value);
    await SyncPrefs.instance.setAutoAfterScan(value);
  }

  /// Turns automatic syncing on or off, and makes it so immediately.
  ///
  /// [AutoSync.resume] rather than waiting for the next launch: a switch that
  /// takes effect later is a switch the user will flick twice trying to work out
  /// whether it did anything.
  Future<void> _setAuto(bool value) async {
    setState(() => _auto = value);
    await SyncPrefs.instance.setAuto(value);
    if (value) {
      await AutoSync.instance.resume();
    } else {
      AutoSync.instance.pause();
    }
  }

  /// Asks how often, from a short list rather than a number field.
  Future<void> _editAutoMinutes() async {
    final int? chosen = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('Sync how often?'),
        children: <Widget>[
          for (final int minutes in kAutoSyncChoices)
            ListTile(
              // The tick marks the current choice without a radio group, which
              // in a dialog that closes on the first tap would only ever be
              // seen mid-dismissal.
              leading: Icon(
                minutes == _autoMinutes
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(describeSyncInterval(minutes)),
              onTap: () => Navigator.of(dialogContext).pop(minutes),
            ),
        ],
      ),
    );
    if (chosen == null) return;

    setState(() => _autoMinutes = chosen);
    await SyncPrefs.instance.setAutoMinutes(chosen);
    // The running timer is on the old interval until it is rebuilt.
    await AutoSync.instance.resume();
  }

  /// One text field in a dialog, validated before it closes.
  Future<String?> _askForText({
    required String title,
    required String hint,
    required String initial,
    required String? Function(String) validate,
    TextInputType? keyboardType,
  }) =>
      showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => _TextPromptDialog(
          title: title,
          hint: hint,
          initial: initial,
          validate: validate,
          keyboardType: keyboardType,
        ),
      );

  /// Username and password together, since one without the other is no use.
  Future<(String, String)?> _askForCredentials() async {
    final (String, String)? result = await showDialog<(String, String)>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _CredentialsDialog(username: _syncUser ?? ''),
    );
    if (result == null) return null;
    if (result.$1.trim().isEmpty || result.$2.isEmpty) {
      _say('Both a username and a password are needed.');
      return null;
    }
    return result;
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Writes the whole database to a workbook and offers it to the share sheet,
  /// which is how it reaches Drive — and from Drive, Google Sheets.
  Future<void> _export() async {
    if (_busyWithData) return;
    setState(() => _exporting = true);
    try {
      final (BackupData data, File file) =
          await withLoadingModal<(BackupData, File)>(
        context: context,
        message: 'Exporting data…',
        subtitle: 'Generating spreadsheet workbook…',
        task: () async {
          final BackupData d = await AppDatabase.instance.exportAll();
          final File f =
              await writeBackup(d, backupFileName(DateTime.now()));
          return (d, f);
        },
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: kXlsxMimeType)],
          subject: 'TU Expense Tracker backup',
          text: '${data.meta['transactions']} transactions, exported '
              '${DateFormat('d MMM yyyy').format(DateTime.now())}.',
        ),
      );
    } catch (error) {
      _say('The export failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Reads a workbook back over the top of everything.
  ///
  /// Nothing is deleted until the file has been decoded, validated and
  /// confirmed, and a copy of what is about to be replaced has been written —
  /// so every way this can fail is a way that leaves the ledger alone.
  Future<void> _restore() async {
    if (_busyWithData) return;

    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a backup workbook',
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx'],
    );
    if (picked == null || !mounted) return;

    setState(() => _restoring = true);
    try {
      final (BackupData? backup, String? unreadable) =
          await withLoadingModal<(BackupData?, String?)>(
        context: context,
        message: 'Reading backup…',
        subtitle: 'Validating spreadsheet data…',
        task: () async =>
            decodeBackupInBackground(await picked.readAsBytes()),
      );
      if (!mounted) return;
      if (backup == null) {
        await showBackupProblems(context, <String>[unreadable!]);
        return;
      }

      final List<String> problems = validateBackup(
        backup,
        appSchemaVersion: kSchemaVersion,
      );
      if (problems.isNotEmpty) {
        await showBackupProblems(context, problems);
        return;
      }

      // Read before asking, so the question can name what is about to go.
      final BackupData current = await AppDatabase.instance.exportAll();
      if (!mounted) return;
      final bool go = await confirmRestore(
        context,
        replacing: current.transactions.length,
        incoming: backup.transactions.length,
      );
      if (!go || !mounted) return;

      final File safety = await withLoadingModal<File>(
        context: context,
        message: 'Restoring backup…',
        subtitle: 'Saving safety copy and restoring records…',
        task: () async {
          final File s = await writeBackup(
            current,
            backupFileName(DateTime.now(), beforeRestore: true),
          );
          await AppDatabase.instance.replaceAll(backup);
          return s;
        },
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Restored'),
          content: Text(
            '${backup.transactions.length} transactions, '
            '${backup.categories.length} categories and '
            '${backup.deleted.length} deleted rows are back.\n\n'
            'What was here before was saved as ${p.basename(safety.path)}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      _say('The restore failed: $error');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// The explicit check. Unlike the launch one this always reports back, so a
  /// press of the button is never met with silence.
  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _status = null;
      _available = null;
    });

    final result = await UpdateService.instance.check();
    final last = await UpdatePrefs.instance.lastChecked();
    if (!mounted) return;

    setState(() {
      _checking = false;
      _lastChecked = last;
      _available = result.release;
      _status = result.failed
          ? result.error
          : result.hasUpdate
              ? null
              : 'Up to date.';
    });

    if (result.hasUpdate) await showUpdateDialog(context, result.release!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = _available;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: <Widget>[
              SettingsHeader('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Theme mode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AppThemeMode>(
                          value: ThemeController.instance.appThemeMode,
                          isExpanded: true,
                          selectedItemBuilder: (BuildContext context) {
                            return AppThemeMode.values.map((AppThemeMode mode) {
                              return Row(
                                children: <Widget>[
                                  Icon(mode.icon, size: 20),
                                  const SizedBox(width: 12),
                                  Text(mode.label),
                                ],
                              );
                            }).toList();
                          },
                          items: AppThemeMode.values.map((AppThemeMode mode) {
                            final bool isSelected =
                                ThemeController.instance.appThemeMode == mode;
                            return DropdownMenuItem<AppThemeMode>(
                              value: mode,
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    mode.icon,
                                    size: 20,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    mode.label,
                                    style: isSelected
                                        ? TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          )
                                        : null,
                                  ),
                                  const Spacer(),
                                  if (isSelected)
                                    Icon(
                                      Icons.check,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (AppThemeMode? mode) {
                            if (mode != null) {
                              ThemeController.instance.setThemeMode(mode);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Accent color',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: AppAccentColor.values.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (BuildContext context, int index) {
                          final AppAccentColor accent =
                              AppAccentColor.values[index];
                          final bool isSelected =
                              ThemeController.instance.accentColor == accent;
                          return Tooltip(
                            message: accent.label,
                            child: InkWell(
                              onTap: () {
                                ThemeController.instance.setAccentColor(accent);
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: accent.seedColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                    width: isSelected ? 3 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? <BoxShadow>[
                                          BoxShadow(
                                            color: accent.seedColor
                                                .withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Icon pack',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AppIconPack>(
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<AppIconPack>>[
                          ButtonSegment<AppIconPack>(
                            value: AppIconPack.emojis,
                            icon: Icon(Icons.emoji_emotions_outlined),
                            label: Text('Emojis'),
                          ),
                          ButtonSegment<AppIconPack>(
                            value: AppIconPack.outlined,
                            icon: Icon(Icons.category_outlined),
                            label: Text('Outlined'),
                          ),
                          ButtonSegment<AppIconPack>(
                            value: AppIconPack.filled,
                            icon: Icon(Icons.category),
                            label: Text('Filled'),
                          ),
                        ],
                        selected: <AppIconPack>{
                          ThemeController.instance.appIconPack,
                        },
                        onSelectionChanged: (Set<AppIconPack> selection) {
                          if (selection.isNotEmpty) {
                            ThemeController.instance.setIconPack(
                              selection.first,
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              SettingsHeader('Preferences'),
              SwitchListTile(
                value: _appLock,
                onChanged: _setAppLock,
                title: const Text('App lock'),
                subtitle: const Text(
                  'Require fingerprint, face, or device screen lock to open the app. Off by default.',
                ),
              ),
              const Divider(height: 16),
              SwitchListTile(
                value: _trackReceived,
                onChanged: _setTrackReceived,
                title: const Text('Track received amounts'),
                subtitle: const Text(
                  'Show incoming credits, refunds, and received money in transactions and dashboard. Off by default.',
                ),
              ),
              const Divider(height: 16),
              SwitchListTile(
                value: _aiFallback,
                onChanged: _setAiFallback,
                title: const Text('On-device AI fallback'),
                subtitle: Text(
                  _isAiModelAvailable
                      ? 'Enabled. Runs locally offline on device CPU when regex patterns fail.'
                      : 'Uses local AI to parse unmatched bank SMS offline. Model download required (~397 MB).',
                ),
              ),
              if (_isAiDownloading) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _downloadProgress != null
                                ? 'Downloading: ${(_downloadProgress! * 100).toStringAsFixed(1)}%'
                                : 'Connecting...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: () {
                              LocalLlmService.instance.cancelDownload();
                              setState(() {
                                _isAiDownloading = false;
                                _downloadProgress = null;
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (_isAiModelAvailable) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.document_scanner, size: 18),
                        label: const Text('Scan existing SMS'),
                        onPressed: _scanExistingSmsForReview,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('Paste transaction'),
                        onPressed: _openPasteTransaction,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: Text(
                          _aiModelSizeBytes != null
                              ? 'Delete model (${(_aiModelSizeBytes! / (1024 * 1024)).toStringAsFixed(0)} MB)'
                              : 'Delete model',
                        ),
                        onPressed: _deleteModel,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Download AI Model (~397 MB)'),
                        onPressed: _startModelDownload,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Select .gguf file'),
                        onPressed: _pickLocalModel,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('Contribute a bank SMS format'),
                subtitle: const Text(
                  'Voluntarily share an anonymized SMS format on GitHub to improve AI & RAG',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ContributeSampleDialog.show(
                  context,
                  rawSms: '',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Simple contribution guide'),
                subtitle: const Text(
                  'Learn how to contribute bank SMS formats on GitHub',
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: GitHubContributionHelper.openReadmeGuide,
              ),
              const Divider(height: 32),
              SettingsHeader('Categorization'),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Merchants & defaults'),
                  subtitle: const Text(
                    'What each merchant is categorised as by default',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MerchantDefaultsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 32),
                SettingsHeader('Cleanup'),
                ListTile(
                  leading: const Icon(Icons.merge_type),
                  title: const Text('Merge merchants'),
                  subtitle: const Text(
                    'Fold several spellings of one shop into a single name',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const MergeNamesScreen(kind: NameKind.merchant),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: const Text('Merge cards & accounts'),
                  subtitle: const Text(
                    'One account can arrive labelled differently by each alert',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const MergeNamesScreen(kind: NameKind.card),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: const Text('Categories'),
                  subtitle: const Text(
                    'Add one, or drop one you never use — its transactions '
                    'move, not go',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CategoriesScreen(),
                    ),
                  ),
                ),
                const Divider(height: 32),
                SettingsHeader('Data'),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('Export data'),
                  subtitle: const Text(
                    'A spreadsheet of everything — and the same file a '
                    'restore reads back',
                  ),
                  trailing: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: _busyWithData ? null : _export,
                          child: const Text('Export'),
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restore from backup'),
                  subtitle: const Text(
                    'Replaces everything in the app with an exported '
                    'workbook',
                  ),
                  trailing: _restoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: _busyWithData ? null : _restore,
                          child: const Text('Restore'),
                        ),
                ),
                const Divider(height: 32),
                SettingsHeader('Server sync'),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server address'),
                  subtitle: Text(_serverUrl?.toString() ?? 'Not set'),
                  onTap: _busyWithData ? null : _editServerUrl,
                ),
                ListTile(
                  leading: const Icon(Icons.smartphone_outlined),
                  title: const Text('Name for this device'),
                  // Shown in the browser's device picker, so it is worth being
                  // able to tell two phones apart.
                  subtitle: Text(_deviceLabel),
                  onTap: _busyWithData ? null : _editDeviceLabel,
                ),
                ListTile(
                  leading: Icon(_syncUser == null
                      ? Icons.person_outline
                      : Icons.verified_user_outlined),
                  title: Text(_syncUser == null ? 'Sign in' : 'Signed in'),
                  subtitle: Text(_syncUser ?? 'Not signed in'),
                  trailing: _syncUser == null
                      ? null
                      : TextButton(
                          onPressed: _busyWithData ? null : _signOut,
                          child: const Text('Sign out'),
                        ),
                  onTap: _busyWithData || _syncUser != null ? null : _signIn,
                ),
                ListTile(
                  leading: const Icon(Icons.network_check_outlined),
                  title: const Text('Test connection'),
                  subtitle: const Text(
                    'Checks the address without needing an account.',
                  ),
                  trailing: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: _busyWithData ? null : _testConnection,
                          child: const Text('Test'),
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Sync now'),
                  subtitle: Text(
                    _syncStatus ??
                        (_lastPushed == null
                            ? 'Never synced'
                            : 'Last synced '
                                '${_checkedFormat.format(_lastPushed!)}'),
                  ),
                  trailing: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: _busyWithData || _syncUser == null
                              ? null
                              : _syncNow,
                          child: const Text('Sync'),
                        ),
                ),
                SwitchListTile(
                  value: _auto,
                  onChanged: _syncUser == null ? null : _setAuto,
                  title: const Text('Sync automatically'),
                  subtitle: Text(
                    'While the app is open: on opening it, when you come back '
                    'to it, ${describeSyncInterval(_autoMinutes).toLowerCase()}, '
                    'and shortly after you change something. This is what '
                    'applies edits made in a browser.',
                  ),
                ),
                if (_auto)
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('How often'),
                    subtitle: Text(describeSyncInterval(_autoMinutes)),
                    enabled: _syncUser != null,
                    onTap: _editAutoMinutes,
                  ),
                SwitchListTile(
                  value: _autoAfterScan,
                  onChanged: _syncUser == null ? null : _setAutoAfterScan,
                  title: const Text('Sync after each inbox scan'),
                  subtitle: const Text(
                    'Uploads as soon as a scan finds something, without waiting '
                    'for the next automatic sync. Off by default.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_table_outlined),
                  title: const Text('Server rolling backups'),
                  subtitle: const Text(
                    'Daily 9:00 PM auto-backups, snapshot history and restore.',
                  ),
                  enabled: _syncUser != null && !_busyWithData,
                  onTap: _syncUser == null || _busyWithData
                      ? null
                      : () => showServerBackupsSheet(
                            context,
                            onChanged: widget.onChanged,
                          ),
                ),
                if (!isFDroidBuild) ...[
                  const Divider(height: 32),
                  SettingsHeader('Updates'),
                  if (_isFdroidPresent)
                    const ListTile(
                      title: Text('Updates managed externally'),
                      subtitle: Text(
                        'An F-Droid or compatible store was detected on this device. Updates are managed through your app store.',
                      ),
                    )
                  else ...[
                    SwitchListTile(
                      value: _autoCheck,
                      onChanged: _setAutoCheck,
                      title: const Text('Check automatically'),
                      subtitle: const Text(
                        'On launch, at most once a week. Disabled by default. '
                        'Nothing is downloaded without asking.',
                      ),
                    ),
                    ListTile(
                      title: const Text('Check for updates'),
                      subtitle: Text(
                        _status ??
                            (_lastChecked == null
                                ? 'Not checked yet'
                                : 'Last checked '
                                    '${_checkedFormat.format(_lastChecked!)}'),
                      ),
                      trailing: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton.tonal(
                              onPressed: _checkNow,
                              child: const Text('Check now'),
                            ),
                    ),
                    if (release != null)
                      ListTile(
                        leading: Icon(
                          Icons.system_update_alt,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text('Version ${release.version} available'),
                        subtitle: const Text('Downloads, then Android installs it'),
                        trailing: FilledButton(
                          onPressed: () => showUpdateDialog(context, release),
                          child: const Text('Install'),
                        ),
                      ),
                  ],
                ],
                const Divider(height: 32),
                SettingsHeader('About'),
                ListTile(
                  title: const Text('TU Expense Tracker'),
                  subtitle: const Text(
                    'Turns bank SMS alerts into a categorised expense ledger.',
                  ),
                ),
                ListTile(
                  title: const Text('Version'),
                  // The build number distinguishes two APKs that report the
                  // same version, which matters while diagnosing an install.
                  subtitle: Text('$_version (build $_build)'),
                ),
                ListTile(
                  title: const Text('Releases'),
                  subtitle: const Text('github.com/$kUpdateRepo'),
                ),
                const SizedBox(height: 24),
              ],
            );
  }
}

/// A single validated text field in a dialog.
///
/// Stateful so that it owns its controller. A controller created beside
/// `showDialog` and disposed once it awaits is disposed too early: showDialog
/// completes when the route *starts* closing, while the dialog is still being
/// built through its exit animation, which throws "A TextEditingController was
/// used after being disposed". A State's dispose runs when the route is gone.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.validate,
    this.keyboardType,
  });

  final String title;
  final String hint;
  final String initial;
  final String? Function(String) validate;
  final TextInputType? keyboardType;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
    // Caret at the end rather than the whole field selected, so typing after a
    // port number does not wipe the address.
  )..selection = TextSelection.collapsed(offset: widget.initial.length);

  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final String? bad = widget.validate(value);
    if (bad == null) {
      Navigator.pop(context, value);
    } else {
      setState(() => _problem = bad);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: _problem,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _submit,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _submit(_controller.text),
            child: const Text('Save'),
          ),
        ],
      );
}

/// Username and password, asked for together.
class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({required this.username});

  final String username;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final TextEditingController _username =
      TextEditingController(text: widget.username);
  final TextEditingController _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, (_username.text, _password.text));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Sign in to your server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _username,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip:
                      _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Signing in can take a few seconds: the server hashes your '
              'password deliberately slowly.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Sign in')),
        ],
      );
}
