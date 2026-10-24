/// On-device LLM service for parsing transactional SMS messages using llama.cpp.
///
/// Runs 100% offline and locally on device CPU. Model weights are never bundled
/// in the APK; they are downloaded or selected by the user on demand.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../../core/email_parser.dart';
import '../../core/ledger_prefs.dart';
import '../../core/parser.dart';
import 'local_rag_retriever.dart';

class LocalLlmService {
  LocalLlmService._();

  static final LocalLlmService instance = LocalLlmService._();

  static const String defaultModelFileName = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';
  static const String defaultModelDownloadUrl =
      'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf';
  static const int minValidModelSizeBytes = 20 * 1024 * 1024; // 20 MB

  LlamaController? _controller;
  String? _loadedModelPath;

  /// Completes when the native generation loop has really ended. A timed-out
  /// parse returns before that, and starting another while it runs aborts the app.
  Future<void> _lastGeneration = Future<void>.value();
  http.Client? _activeDownloadClient;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  /// Gets the directory where local models are stored.
  Future<Directory> getModelDirectory() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory modelsDir = Directory(p.join(appDir.path, 'models'));
    if (!modelsDir.existsSync()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// Default model file location.
  Future<File> getDefaultModelFile() async {
    final Directory dir = await getModelDirectory();
    return File(p.join(dir.path, defaultModelFileName));
  }

  /// Returns the path to the currently active model (custom or default).
  Future<String?> getActiveModelPath() async {
    if (!Platform.isAndroid) return null;
    try {
      final String? custom = await LedgerPrefs.instance.customModelPath();
      if (custom != null && custom.isNotEmpty) {
        final File customFile = File(custom);
        if (customFile.existsSync() && customFile.lengthSync() >= minValidModelSizeBytes) {
          return custom;
        }
      }
      final File defaultFile = await getDefaultModelFile();
      if (defaultFile.existsSync() && defaultFile.lengthSync() >= minValidModelSizeBytes) {
        return defaultFile.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Checks if a valid model file is available on the device.
  Future<bool> isModelAvailable() async {
    final String? path = await getActiveModelPath();
    return path != null;
  }

  /// Returns the size in bytes of the active model file, or null if missing.
  Future<int?> getModelSizeBytes() async {
    final String? path = await getActiveModelPath();
    if (path == null) return null;
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  /// Streams the download progress (0.0 to 1.0) of the default Qwen model.
  Stream<double> downloadDefaultModel() async* {
    if (_isDownloading) {
      throw StateError('A model download is already in progress.');
    }
    _isDownloading = true;

    final File destFile = await getDefaultModelFile();
    final File partFile = File('${destFile.path}.part');

    final client = http.Client();
    _activeDownloadClient = client;

    try {
      final request = http.Request('GET', Uri.parse(defaultModelDownloadUrl));
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download failed with HTTP ${response.statusCode}');
      }

      final int totalBytes = response.contentLength ?? 397 * 1024 * 1024;
      int receivedBytes = 0;

      final IOSink sink = partFile.openWrite();

      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          yield (receivedBytes / totalBytes).clamp(0.0, 1.0);
        }
      }

      await sink.flush();
      await sink.close();

      if (destFile.existsSync()) {
        await destFile.delete();
      }
      await partFile.rename(destFile.path);
      await LedgerPrefs.instance.setAiFallbackEnabled(true);
      yield 1.0;
    } catch (e) {
      if (partFile.existsSync()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _isDownloading = false;
      _activeDownloadClient?.close();
      _activeDownloadClient = null;
    }
  }

  /// Cancels an in-progress model download.
  void cancelDownload() {
    _activeDownloadClient?.close();
    _activeDownloadClient = null;
    _isDownloading = false;
  }

  /// Deletes the local default model file to reclaim storage.
  Future<void> deleteDefaultModel() async {
    await unload();
    final File file = await getDefaultModelFile();
    if (file.existsSync()) {
      await file.delete();
    }
    final File part = File('${file.path}.part');
    if (part.existsSync()) {
      await part.delete();
    }
    await LedgerPrefs.instance.setCustomModelPath(null);
  }

  /// Lets the user pick a local GGUF model file using the system file picker.
  Future<bool> pickCustomModel() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: 'Select GGUF Model File',
    );
    if (picked != null && picked.path != null) {
      final String path = picked.path!;
      final File file = File(path);
      if (file.existsSync() && file.lengthSync() >= minValidModelSizeBytes) {
        await unload();
        await LedgerPrefs.instance.setCustomModelPath(path);
        await LedgerPrefs.instance.setAiFallbackEnabled(true);
        return true;
      }
    }
    return false;
  }

  /// Unloads the model from RAM.
  Future<void> unload() async {
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (e) {
        debugPrint('[LocalLlmService] Error unloading model: $e');
      }
      _controller = null;
      _loadedModelPath = null;
    }
  }

  /// Ensures the model is loaded into memory on Android.
  Future<void> _ensureLoaded() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('On-device LLM inference is currently supported on Android.');
    }
    final String? modelPath = await getActiveModelPath();
    if (modelPath == null) {
      throw StateError('No local model file found. Please download or select a GGUF model in Settings.');
    }

    if (_controller != null && _loadedModelPath == modelPath) {
      final bool loaded = await _controller!.isModelLoaded();
      if (loaded) return;
    }

    await unload();
    final controller = LlamaController();
    await controller.loadModel(
      modelPath: modelPath,
      threads: 4,
      contextSize: 1024,
    );
    _controller = controller;
    _loadedModelPath = modelPath;
  }

  /// Parses a bank transaction SMS or email alert using the local on-device LLM.
  Future<ParsedSms?> parseTransactionText(
    String messageText, {
    DateTime? receivedAt,
    String messageType = 'Message',
  }) async {
    if (!Platform.isAndroid) return null;

    await _ensureLoaded();
    if (_controller == null) return null;
    await _lastGeneration.timeout(const Duration(seconds: 60), onTimeout: () {});
    // Each parse is a fresh question; leftover tokens from the last one overflow the 1024 context.
    await _controller!.clearContext();

    final String systemPrompt =
        await LocalRagRetriever.instance.buildAugmentedSystemPrompt(messageText);

    final List<ChatMessage> messages = <ChatMessage>[
      ChatMessage(role: 'system', content: systemPrompt),
      ChatMessage(role: 'user', content: '$messageType: "$messageText"'),
    ];

    final StringBuffer buffer = StringBuffer();
    final completer = Completer<String>();

    final Stream<String> stream = _controller!.generateChat(
      messages: messages,
      temperature: 0.1,
      maxTokens: 256,
    );

    final Completer<void> finished = Completer<void>();
    _lastGeneration = finished.future;
    final StreamSubscription<String> sub = stream.listen(
      (String token) {
        buffer.write(token);
      },
      onError: (Object err) {
        if (!completer.isCompleted) completer.completeError(err);
        if (!finished.isCompleted) finished.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(buffer.toString());
        if (!finished.isCompleted) finished.complete();
      },
    );

    try {
      final String responseText = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _controller?.stop();
          return buffer.toString();
        },
      );
      return parseRawJson(responseText, fallbackDate: receivedAt ?? DateTime.now());
    } finally {
      // After a timeout keep listening, so the native loop's final onDone still
      // releases [_lastGeneration].
      if (finished.isCompleted) await sub.cancel();
    }
  }

  /// Parses a bank SMS message using the local on-device LLM.
  Future<ParsedSms?> parseSms(String smsBody, {DateTime? receivedAt}) =>
      parseTransactionText(smsBody, receivedAt: receivedAt, messageType: 'SMS');

  /// Parses a bank transaction email alert using the local on-device LLM.
  /// Automatically strips HTML tags and caps context length to ensure high fidelity.
  Future<ParsedSms?> parseEmail(String emailBody, {DateTime? receivedAt}) async {
    final String clean = EmailParser.stripHtml(emailBody);
    final String trimmed = clean.length > 1500 ? clean.substring(0, 1500) : clean;
    return parseTransactionText(trimmed, receivedAt: receivedAt, messageType: 'Email');
  }

  /// Parses model JSON output into a [ParsedSms]. Public for unit testing.
  static ParsedSms? parseRawJson(String rawText, {DateTime? fallbackDate}) {
    final String trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    // Extract JSON block between first '{' and last '}'
    final int start = trimmed.indexOf('{');
    final int end = trimmed.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;

    final String jsonStr = trimmed.substring(start, end + 1);
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;

      final bool isTransaction = decoded['is_transaction'] == true;
      if (!isTransaction) return null;

      final dynamic rawAmount = decoded['amount'];
      double? amount;
      if (rawAmount is num) {
        amount = rawAmount.toDouble();
      } else if (rawAmount is String) {
        amount = double.tryParse(rawAmount.replaceAll(',', ''));
      }
      if (amount == null || amount <= 0) return null;

      final String typeStr = (decoded['type'] as String? ?? 'debit').toLowerCase();
      final TxnDirection direction =
          typeStr.contains('credit') ? TxnDirection.credit : TxnDirection.debit;

      final String merchant = (decoded['merchant'] as String? ?? 'Unknown').trim();
      final String? account = decoded['account']?.toString();
      final String paymentType = (account != null && account.isNotEmpty)
          ? 'A/C *$account'
          : 'Card/UPI';

      final String reference = (decoded['reference']?.toString() ?? '').trim();

      DateTime date = fallbackDate ?? DateTime.now();
      final String? rawDate = decoded['date']?.toString();
      if (rawDate != null && rawDate.isNotEmpty) {
        final DateTime? parsed = DateTime.tryParse(rawDate);
        if (parsed != null) {
          date = parsed;
        }
      }

      return ParsedSms(
        amount: amount,
        paymentType: paymentType,
        merchant: merchant.isEmpty ? 'Unknown' : merchant,
        date: date,
        direction: direction,
        reference: reference,
        templateId: 'ai-llm-local',
        hasExplicitTime: false,
      );
    } catch (e) {
      debugPrint('[LocalLlmService] Failed to parse JSON: $e');
      return null;
    }
  }
}
