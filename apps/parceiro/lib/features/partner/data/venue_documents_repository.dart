import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';

class VenueDocumentsFailure implements Exception {
  const VenueDocumentsFailure(this.code);

  final String code;
}

class VenueDocumentItem {
  const VenueDocumentItem({
    required this.id,
    required this.status,
    required this.type,
    required this.title,
    required this.hosted,
    required this.upload,
    this.description = '',
    this.onboardingUrl,
  });

  final String id;
  final String status;
  final String type;
  final String title;
  final String description;
  final String? onboardingUrl;
  final bool hosted;
  final bool upload;
}

class VenueDocumentFile {
  const VenueDocumentFile({required this.bytes});

  final Uint8List bytes;
}

/// Escolha do arquivo. Os testes trocam o provedor.
abstract class VenueDocumentPicker {
  Future<VenueDocumentFile?> pick();
}

class FileVenueDocumentPicker implements VenueDocumentPicker {
  const FileVenueDocumentPicker();

  @override
  Future<VenueDocumentFile?> pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    if (bytes.isEmpty) return null;
    return VenueDocumentFile(bytes: bytes);
  }
}

class VenueDocumentsView {
  const VenueDocumentsView({
    required this.visible,
    required this.known,
    required this.approved,
    required this.documentation,
    required this.general,
    required this.documents,
    this.onboardingUrl,
    this.message,
  });

  final bool visible;
  final bool known;
  final bool approved;
  final String documentation;
  final String general;
  final String? onboardingUrl;
  final List<VenueDocumentItem> documents;
  final String? message;

  bool get blocksWithdraw => visible && known && !approved;

  static const unavailable = VenueDocumentsView(
    visible: true,
    known: false,
    approved: false,
    documentation: 'UNKNOWN',
    general: 'UNKNOWN',
    documents: [],
    message: 'unavailable',
  );

  static const hidden = VenueDocumentsView(
    visible: false,
    known: false,
    approved: false,
    documentation: 'UNKNOWN',
    general: 'UNKNOWN',
    documents: [],
  );

  factory VenueDocumentsView.fromJson(Map<String, dynamic> json) {
    return VenueDocumentsView(
      visible: true,
      known: json['known'] == true,
      approved: json['approved'] == true,
      documentation: json['documentation']?.toString() ?? 'UNKNOWN',
      general: json['general']?.toString() ?? 'UNKNOWN',
      onboardingUrl: _url(json['onboarding_url']),
      documents: [
        for (final row in _rows(json['documents']))
          VenueDocumentItem(
            id: row['id']?.toString() ?? '',
            status: row['status']?.toString() ?? 'UNKNOWN',
            type: row['type']?.toString() ?? '',
            title: row['title']?.toString() ?? '',
            description: row['description']?.toString() ?? '',
            onboardingUrl: _url(row['onboarding_url']),
            hosted: row['hosted'] == true,
            upload: row['upload'] == true,
          ),
      ],
    );
  }
}

abstract class VenueDocumentsRepository {
  Future<VenueDocumentsView> load(String venueId);

  Future<VenueDocumentsView> upload({
    required String venueId,
    required String documentId,
    required Uint8List bytes,
  });
}

class MemoryVenueDocumentsRepository implements VenueDocumentsRepository {
  MemoryVenueDocumentsRepository(this.view);

  VenueDocumentsView view;
  final List<String> uploads = [];

  @override
  Future<VenueDocumentsView> load(String venueId) async => view;

  @override
  Future<VenueDocumentsView> upload({
    required String venueId,
    required String documentId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw const VenueDocumentsFailure('arquivo');
    final item = view.documents.cast<VenueDocumentItem?>().firstWhere(
      (row) => row?.id == documentId,
      orElse: () => null,
    );
    if (item == null || item.hosted || !item.upload) {
      throw const VenueDocumentsFailure('onboarding');
    }
    uploads.add(documentId);
    view = VenueDocumentsView(
      visible: true,
      known: true,
      approved: false,
      documentation: 'AWAITING_APPROVAL',
      general: 'PENDING',
      documents: [
        for (final row in view.documents)
          if (row.id == documentId)
            VenueDocumentItem(
              id: row.id,
              status: 'PENDING',
              type: row.type,
              title: row.title,
              description: row.description,
              hosted: false,
              upload: false,
            )
          else
            row,
      ],
    );
    return view;
  }
}

class SupabaseVenueDocumentsRepository implements VenueDocumentsRepository {
  @override
  Future<VenueDocumentsView> load(String venueId) async {
    try {
      return VenueDocumentsView.fromJson(
        await _invoke({'action': 'list', 'venue_id': venueId}),
      );
    } on VenueDocumentsFailure catch (error) {
      if (error.code == 'not owner') return VenueDocumentsView.hidden;
      return VenueDocumentsView.unavailable;
    } on Object {
      return VenueDocumentsView.unavailable;
    }
  }

  @override
  Future<VenueDocumentsView> upload({
    required String venueId,
    required String documentId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > 2000000) {
      throw const VenueDocumentsFailure('arquivo');
    }
    return VenueDocumentsView.fromJson(
      await _invoke({
        'action': 'upload',
        'venue_id': venueId,
        'document_id': documentId,
        'content_base64': base64Encode(bytes),
      }),
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'venue-documents',
        body: body,
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw VenueDocumentsFailure(data['error'].toString());
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const VenueDocumentsFailure('erro');
    } on VenueDocumentsFailure {
      rethrow;
    } on Object catch (error) {
      throw VenueDocumentsFailure(_code(error));
    }
  }
}

String _code(Object error) {
  try {
    final details = (error as dynamic).details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
  } on Object {
    // O texto abaixo ainda pode trazer o código estável.
  }
  final text = error.toString();
  for (final code in const [
    'onboarding',
    'arquivo',
    'reauth',
    'mfa',
    'not owner',
    'sem subconta',
    'reserva',
    'status',
  ]) {
    if (text.contains(code)) return code;
  }
  return 'erro';
}

String? _url(Object? value) {
  final text = value?.toString() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https') return null;
  return text;
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List) return const [];
  return [
    for (final row in value)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

final venueDocumentsRepositoryProvider = Provider<VenueDocumentsRepository>((
  ref,
) {
  if (ref.watch(backendPlanProvider).connectsSupabase) {
    return SupabaseVenueDocumentsRepository();
  }
  return MemoryVenueDocumentsRepository(VenueDocumentsView.hidden);
});

final venueDocumentPickerProvider = Provider<VenueDocumentPicker>((ref) {
  return const FileVenueDocumentPicker();
});

String venueDocumentFailureMessage(String code) {
  return switch (code) {
    'onboarding' => 'Esse documento se envia no site do Asaas.',
    'arquivo' => 'Escolha um PDF, JPG ou PNG de até 2 MB.',
    'reauth' || 'mfa' => 'Confirme que é você para enviar o arquivo.',
    'sem subconta' => 'A casa ainda não tem subconta.',
    'reserva' => 'Essa conta não recebe documento.',
    'status' => 'Esse documento não está pendente.',
    _ => 'Não foi possível consultar os documentos.',
  };
}
