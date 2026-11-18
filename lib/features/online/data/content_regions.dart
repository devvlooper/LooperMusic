/// Known ISO 3166-1 alpha-2 content regions supported by YouTube Music.
class ContentRegion {
  final String code;
  final String name;

  const ContentRegion(this.code, this.name);
}

abstract final class ContentRegions {
  static const List<ContentRegion> all = [
    ContentRegion('US', 'United States'),
    ContentRegion('IN', 'India'),
    ContentRegion('GB', 'United Kingdom'),
    ContentRegion('CA', 'Canada'),
    ContentRegion('AU', 'Australia'),
    ContentRegion('DE', 'Germany'),
    ContentRegion('FR', 'France'),
    ContentRegion('JP', 'Japan'),
    ContentRegion('KR', 'South Korea'),
    ContentRegion('BR', 'Brazil'),
    ContentRegion('MX', 'Mexico'),
    ContentRegion('ES', 'Spain'),
    ContentRegion('IT', 'Italy'),
    ContentRegion('NL', 'Netherlands'),
    ContentRegion('SE', 'Sweden'),
    ContentRegion('NO', 'Norway'),
    ContentRegion('DK', 'Denmark'),
    ContentRegion('FI', 'Finland'),
    ContentRegion('PL', 'Poland'),
    ContentRegion('RU', 'Russia'),
    ContentRegion('TR', 'Turkey'),
    ContentRegion('ID', 'Indonesia'),
    ContentRegion('PH', 'Philippines'),
    ContentRegion('VN', 'Vietnam'),
    ContentRegion('TH', 'Thailand'),
    ContentRegion('MY', 'Malaysia'),
    ContentRegion('SG', 'Singapore'),
    ContentRegion('NZ', 'New Zealand'),
    ContentRegion('IE', 'Ireland'),
    ContentRegion('AT', 'Austria'),
    ContentRegion('CH', 'Switzerland'),
    ContentRegion('BE', 'Belgium'),
    ContentRegion('PT', 'Portugal'),
    ContentRegion('AR', 'Argentina'),
    ContentRegion('CL', 'Chile'),
    ContentRegion('CO', 'Colombia'),
    ContentRegion('ZA', 'South Africa'),
    ContentRegion('AE', 'United Arab Emirates'),
    ContentRegion('SA', 'Saudi Arabia'),
    ContentRegion('EG', 'Egypt'),
    ContentRegion('NG', 'Nigeria'),
    ContentRegion('KE', 'Kenya'),
    ContentRegion('PK', 'Pakistan'),
    ContentRegion('BD', 'Bangladesh'),
    ContentRegion('LK', 'Sri Lanka'),
    ContentRegion('NP', 'Nepal'),
  ];

  static String nameFor(String code) {
    final upper = code.trim().toUpperCase();
    for (final r in all) {
      if (r.code == upper) return r.name;
    }
    return upper;
  }
}
