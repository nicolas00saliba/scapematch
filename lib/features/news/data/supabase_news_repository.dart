import 'package:scapematch/core/supabase/row_values.dart';
import 'package:scapematch/features/catalog/domain/feature_order.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/news/data/news_repository.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _newsColumns =
    'id, venue_id, title, summary, category, game_type, image_url, '
    'source_kind, source_url, published_at, carousel_rank';

class SupabaseNewsRepository implements NewsRepository {
  SupabaseNewsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<NewsItem>> list({
    required String? cityId,
    NewsCategory? category,
  }) async {
    if (cityId == null || cityId.isEmpty) return const [];
    final venues = await _houses(cityId);
    if (venues.isEmpty) return const [];
    final rows = await _client
        .from('news_items')
        .select(_newsColumns)
        .inFilter('venue_id', venues.keys.toList())
        .order('published_at', ascending: false);
    final cityName = await _cityName(cityId);
    final items = [
      for (final row in rows) _item(row, venues, cityId, cityName),
    ];
    if (category == null) return items;
    return [
      for (final item in items)
        if (item.category == category) item,
    ];
  }

  @override
  Future<NewsItem?> getById(String id) async {
    final row = await _client
        .from('news_items')
        .select(_newsColumns)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final venueId = textOf(row['venue_id']);
    final venue = await _client
        .from('venues_vitrine')
        .select('id, name, city_id, status')
        .eq('id', venueId)
        .maybeSingle();
    if (venue == null || venue['status'] != 'approved') return null;
    final cityId = textOf(venue['city_id']);
    return _item(
      row,
      {venueId: textOf(venue['name'])},
      cityId,
      await _cityName(cityId),
    );
  }

  Future<Map<String, String>> _houses(String cityId) async {
    final rows = await _client
        .from('venues_vitrine')
        .select('id, name, city_id, status')
        .eq('city_id', cityId)
        .eq('status', 'approved');
    return {for (final row in rows) row['id'] as String: textOf(row['name'])};
  }

  Future<String> _cityName(String cityId) async {
    final row = await _client
        .from('cities')
        .select('name')
        .eq('id', cityId)
        .maybeSingle();
    return row == null ? cityId : textOf(row['name']);
  }

  NewsItem _item(
    Map<String, dynamic> row,
    Map<String, String> houses,
    String cityId,
    String cityName,
  ) {
    final image = textOf(row['image_url']).trim();
    return NewsItem(
      id: row['id'] as String,
      title: textOf(row['title']),
      summary: textOf(row['summary']),
      category: newsCategoryOf(textOf(row['category'])),
      houseName: houses[textOf(row['venue_id'])] ?? 'Casa',
      cityId: cityId,
      cityName: cityName,
      publishedAt: dateTimeOf(row['published_at']) ?? DateTime.now(),
      sourceKind: newsSourceOf(textOf(row['source_kind'])),
      image: image.isEmpty ? null : image,
      sourceUrl: textOf(row['source_url']).trim().isEmpty
          ? null
          : textOf(row['source_url']),
      gameType: textOf(row['game_type']).isEmpty
          ? GameTypes.escapeRoom
          : textOf(row['game_type']),
      carouselRank: optionalRank(row['carousel_rank']),
    );
  }
}

NewsCategory newsCategoryOf(String raw) {
  return switch (raw) {
    'new_room' => NewsCategory.newRoom,
    'schedule' => NewsCategory.schedule,
    'event' => NewsCategory.event,
    _ => NewsCategory.promotion,
  };
}

NewsSourceKind newsSourceOf(String raw) {
  return switch (raw) {
    'website' => NewsSourceKind.website,
    'instagram' => NewsSourceKind.instagram,
    _ => NewsSourceKind.manual,
  };
}
