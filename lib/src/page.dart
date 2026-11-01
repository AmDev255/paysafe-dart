part of 'client.dart';

/// One page of a cursor-paginated list. Iterate [data]; [autoPaging] walks every page.
class Page<T extends ApiObject> extends Iterable<T> {
  Page._(
      this.data, this.hasMore, this.nextCursor, this.lastResponse, this._next);

  final List<T> data;
  final bool hasMore;
  final String? nextCursor;
  final ApiResponse lastResponse;
  final Future<Page<T>> Function(String cursor)? _next;

  @override
  Iterator<T> get iterator => data.iterator;

  T operator [](int index) => data[index];

  /// The following page, or null when this was the last one.
  Future<Page<T>?> nextPage() async {
    final cursor = nextCursor;
    if (!hasMore || cursor == null || _next == null) return null;
    return _next(cursor);
  }

  /// Every item on this page and all following pages, fetched lazily.
  Stream<T> autoPaging() async* {
    Page<T>? page = this;
    while (page != null) {
      yield* Stream.fromIterable(page.data);
      page = await page.nextPage();
    }
  }

  static Page<T> _fromResponse<T extends ApiObject>(
    ApiResponse response,
    T Function(Map<String, dynamic>) make,
    Future<Page<T>> Function(String cursor)? next,
  ) {
    final root = response.json;
    final items = <T>[];
    final data = root?['data'];
    if (data is List) {
      for (final element in data) {
        if (element is Map<String, dynamic>) {
          items.add(make(element)..lastResponse = response);
        }
      }
    }
    final cursor = root?['next_cursor'];
    return Page._(items, root?['has_more'] == true,
        cursor is String ? cursor : null, response, next);
  }
}
