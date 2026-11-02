int? nonNegativeCount(Object? value) =>
    value is int && value >= 0 ? value : null;
