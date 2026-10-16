/// Local on-device RAG retriever for augmenting the local LLM prompt.
///
/// Retrieves relevant few-shot bank SMS exemplars and user account/merchant context
/// to maximize JSON parsing accuracy while staying strictly under the 1024 token limit.
/// 100% offline, zero network requests, zero cloud database dependencies.
library;

import 'dart:convert';
import 'dart:io';

import '../../core/rag_exemplars.dart';
import '../database.dart';

class LocalRagRetriever {
  LocalRagRetriever._();

  static final LocalRagRetriever instance = LocalRagRetriever._();

  static const String baseSystemInstructions =
      'You are an expert bank transaction parser. Extract transaction details from the bank notification (SMS or email) into JSON format.\n'
      'Output ONLY a single valid JSON object with the following keys:\n'
      '"is_transaction": true or false,\n'
      '"type": "debit" if money was sent, spent, debited, paid, withdrawn, or transferred out; "credit" if money was received, credited, deposited, or refunded,\n'
      '"amount": numeric amount (e.g. 90.0) or null,\n'
      '"currency": "INR",\n'
      '"merchant": recipient, payee, or vendor name or null,\n'
      '"account": card number or account number (e.g. "4668") or null,\n'
      '"reference": RRN, UTR, or UPI reference number or null,\n'
      '"date": transaction date (YYYY-MM-DD) or null\n'
      'Do not include any explanation or thoughts. Output pure JSON only.';

  /// Constructs an augmented prompt with retrieved exemplars and known context.
  Future<String> buildAugmentedSystemPrompt(
    String messageText, {
    AppDatabase? databaseOverride,
  }) async {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(baseSystemInstructions);

    // 1. Retrieve known accounts & merchants from local SQLite if available.
    List<String> knownAccounts = <String>[];
    List<String> knownMerchants = <String>[];

    try {
      if (Platform.isAndroid || databaseOverride != null) {
        final AppDatabase db = databaseOverride ?? AppDatabase.instance;
        final accounts = await db.paymentMethods();
        knownAccounts = accounts
            .where((a) => a.contains('*') || a.toLowerCase().contains('card') || a.toLowerCase().contains('a/c'))
            .take(5)
            .toList();
        final merchants = await db.topMerchants(limit: 8);
        knownMerchants = merchants.where((m) => m.isNotEmpty && m != 'Unknown').take(8).toList();
      }
    } catch (_) {
      // Graceful fallback if database is not initialized (e.g. unit tests)
    }

    if (knownAccounts.isNotEmpty || knownMerchants.isNotEmpty) {
      buffer.writeln('\n[User Context]');
      if (knownAccounts.isNotEmpty) {
        buffer.writeln('Known Accounts: ${knownAccounts.join(", ")}');
      }
      if (knownMerchants.isNotEmpty) {
        buffer.writeln('Known Merchants: ${knownMerchants.join(", ")}');
      }
    }

    // 2. Retrieve top-2 matching exemplars from curated bank knowledge bank.
    final List<RagExemplar> exemplars = RagExemplars.findBestExemplars(messageText, limit: 2);
    if (exemplars.isNotEmpty) {
      buffer.writeln('\n[Reference Examples]');
      for (int i = 0; i < exemplars.length; i++) {
        final ex = exemplars[i];
        buffer.writeln('Example ${i + 1} (${ex.bank}):');
        buffer.writeln('Input: "${ex.rawSms}"');
        buffer.writeln('Output: ${jsonEncode(ex.expectedJson)}');
      }
    }

    return buffer.toString().trim();
  }
}
