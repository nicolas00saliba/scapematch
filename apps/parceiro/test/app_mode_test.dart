import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/supabase_partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';

void main() {
  test('o modo real do Parceiro não monta o livro de exemplo', () {
    var sampleBuilt = false;
    final container = ProviderContainer(
      overrides: [
        backendPlanProvider.overrideWithValue(planFor(AppMode.real)),
        fakeDatabaseProvider.overrideWith((ref) {
          sampleBuilt = true;
          return buildSampleDatabase(now: DateTime.utc(2026));
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(partnerRepositoryProvider),
      isA<SupabasePartnerRepository>(),
    );
    expect(sampleBuilt, isFalse);
    expect(scapeUsesLiveBackend, isFalse);
  });

  test('a demonstração do Parceiro não usa o repositório Supabase', () async {
    final previous = scapeUsesLiveBackend;
    addTearDown(() => scapeUsesLiveBackend = previous);
    var called = false;
    await applyBackendPlan(
      AppMode.demo,
      startSupabase: () async {
        called = true;
      },
    );

    final container = ProviderContainer(
      overrides: [backendPlanProvider.overrideWithValue(planFor(AppMode.demo))],
    );
    addTearDown(container.dispose);

    final desk = container.read(partnerRepositoryProvider);
    expect(desk, isA<PartnerRepository>());
    expect(desk, isNot(isA<SupabasePartnerRepository>()));
    expect(called, isFalse);
  });
}
