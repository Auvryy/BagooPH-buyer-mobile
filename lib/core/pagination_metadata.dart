import 'web_session.dart';

const maxBuyerPaginationPage = 1000000;

class PaginationMetadata {
  const PaginationMetadata({
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.from,
    this.to,
  });

  final int currentPage;
  final int lastPage;
  final int total;
  final int? from;
  final int? to;
}

PaginationMetadata? parseContractPaginationMetadata(
  dynamic value, {
  required int rowCount,
  required int requestedPage,
  required int pageSize,
}) {
  if (requestedPage < 1 ||
      requestedPage > maxBuyerPaginationPage ||
      pageSize < 1 ||
      pageSize > 100 ||
      rowCount < 0 ||
      rowCount > pageSize) {
    return null;
  }

  final page = mapOf(value);
  final pagination = parsePaginationMetadata(
    page,
    rowCount: rowCount,
    requirePageNumbers: true,
  );
  final total = page['total'];
  if (pagination == null ||
      total is! int ||
      total < 0 ||
      total > maxBuyerPaginationPage * pageSize ||
      page['per_page'] != pageSize) {
    return null;
  }

  final expectedLast = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
  final expectedCurrent = requestedPage > expectedLast
      ? expectedLast
      : requestedPage;
  final remaining = total - (expectedCurrent - 1) * pageSize;
  final expectedRows = remaining <= 0
      ? 0
      : remaining < pageSize
      ? remaining
      : pageSize;
  final expectedFrom = expectedRows == 0
      ? null
      : (expectedCurrent - 1) * pageSize + 1;
  final expectedTo = expectedRows == 0
      ? null
      : expectedFrom! + expectedRows - 1;

  if (pagination.lastPage != expectedLast ||
      pagination.currentPage != expectedCurrent ||
      rowCount != expectedRows ||
      pagination.from != expectedFrom ||
      pagination.to != expectedTo) {
    return null;
  }
  return pagination;
}

bool isValidBuyerPageRequest(int page) =>
    page >= 1 && page <= maxBuyerPaginationPage;

PaginationMetadata? parsePaginationMetadata(
  dynamic value, {
  required int rowCount,
  bool requirePageNumbers = false,
}) {
  if (rowCount < 0) return null;
  final page = mapOf(value);
  final data = page['data'];
  if (data is! List || data.length != rowCount) return null;
  if (requirePageNumbers &&
      (page['current_page'] == null || page['last_page'] == null)) {
    return null;
  }

  int? integer(Object? value, {required int minimum}) =>
      value is int && value >= minimum ? value : null;
  int? optionalPositive(Object? value) =>
      value == null ? null : integer(value, minimum: 1);

  final current = page['current_page'] == null
      ? 1
      : integer(page['current_page'], minimum: 1);
  final last = page['last_page'] == null
      ? 1
      : integer(page['last_page'], minimum: 1);
  final total = page['total'] == null
      ? rowCount
      : integer(page['total'], minimum: 0);
  final from = optionalPositive(page['from']);
  final to = optionalPositive(page['to']);

  if (current == null ||
      last == null ||
      total == null ||
      page['from'] != null && from == null ||
      page['to'] != null && to == null ||
      from != null && to != null && from > to ||
      page['total'] != null &&
          (from != null && from > total || to != null && to > total)) {
    return null;
  }
  return PaginationMetadata(
    currentPage: current,
    lastPage: last,
    total: total,
    from: from,
    to: to,
  );
}
