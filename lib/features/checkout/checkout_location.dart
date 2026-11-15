String normalizeCheckoutPlace(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String checkoutCityKey(String? value) {
  final normalized = normalizeCheckoutPlace(value)
      .replaceAll(RegExp(r'[.,]'), '');
  return normalized
      .replaceFirst(RegExp(r'^(?:city|municipality)\s+of\s+'), '')
      .replaceFirst(RegExp(r'\s+(?:city|municipality)$'), '')
      .trim();
}

bool hasValidCheckoutPostalCode(String? value) =>
    RegExp(r'^[0-9]{4}$').hasMatch((value ?? '').trim());

List<Map<String, dynamic>> matchingPickupHubs(
  List<Map<String, dynamic>> hubs, {
  required bool hasCompanyContract,
  required int? companyId,
  required String? province,
  required String? city,
  required String? postalCode,
  String? barangay,
}) {
  if (hasCompanyContract && companyId == null) return const [];
  final normProvince = normalizeCheckoutPlace(province);
  final normCity = normalizeCheckoutPlace(city);
  final postal = (postalCode ?? '').trim();
  final normBarangay = normalizeCheckoutPlace(barangay);
  if (normProvince.isEmpty ||
      normCity.isEmpty ||
      !hasValidCheckoutPostalCode(postal)) {
    return const [];
  }

  return hubs.where((hub) {
    if (hasCompanyContract && hub['logistics_company_id'] != companyId) {
      return false;
    }
    final hubProvince = hub['province']?.toString();
    if (hubProvince != null &&
        hubProvince.trim().isNotEmpty &&
        normalizeCheckoutPlace(hubProvince) != normProvince) {
      return false;
    }
    final rawPostalCodes = hub['postal_codes'];
    final postalCodes = rawPostalCodes is List
        ? rawPostalCodes
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    if (postalCodes.isNotEmpty) {
      if (!postalCodes.contains(postal)) return false;
    } else if (checkoutCityKey(hub['city_municipality']?.toString()) !=
        checkoutCityKey(normCity)) {
      return false;
    }

    final rawBarangays = hub['coverage_barangays'];
    final coverageBarangays = rawBarangays is List
        ? rawBarangays
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    if (coverageBarangays.isNotEmpty && normBarangay.isNotEmpty) {
      if (!coverageBarangays.any(
        (covered) => normalizeCheckoutPlace(covered) == normBarangay,
      )) {
        return false;
      }
    }
    return true;
  }).toList();
}

String? defaultPickupHubId(
  List<Map<String, dynamic>> hubs,
  String? selectedHubId,
) {
  if (selectedHubId != null &&
      selectedHubId.isNotEmpty &&
      hubs.any((hub) => hub['id'].toString() == selectedHubId)) {
    return selectedHubId;
  }
  return hubs.length == 1 ? hubs.single['id'].toString() : null;
}

double estimateSelfPickupFeeFromDoorstep(
  double doorstepFee, {
  String model = 'dedicated_fleet',
}) {
  final cents = (doorstepFee * 100).round().clamp(0, 1 << 30);
  final delivery = model == 'standard'
      ? cents ~/ 2
      : (cents ~/ 12) * 5 + (((cents % 12) * 5) ~/ 12);
  return (cents - delivery) / 100;
}
