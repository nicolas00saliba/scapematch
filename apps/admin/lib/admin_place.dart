import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AdminSection { casas, jogadores, regras, ganhos, destaques, auditoria }

class AdminPlace {
  const AdminPlace({this.section = AdminSection.casas, this.id});

  final AdminSection section;
  final String? id;
}

class AdminPlaceController extends Notifier<AdminPlace> {
  @override
  AdminPlace build() => const AdminPlace();

  void go(AdminSection section) => state = AdminPlace(section: section);

  void open(String id) => state = AdminPlace(section: state.section, id: id);

  void close() => state = AdminPlace(section: state.section);
}

final adminPlaceProvider = NotifierProvider<AdminPlaceController, AdminPlace>(
  AdminPlaceController.new,
);
