import 'indexed_item.dart';

class SearchResult {
  const SearchResult({
    required this.item,
    required this.score,
    required this.snippet,
  });

  final IndexedItem item;
  final double score;
  final String snippet;
}
