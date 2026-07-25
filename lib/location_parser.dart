import 'models.dart';

class LocationParseException implements Exception {
  const LocationParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

ActivityLocation? parseActivityLocation(String nameInput, String input) {
  final name = nameInput.trim();
  final coordinates = input.trim();
  if (name.isEmpty && coordinates.isEmpty) return null;
  if (coordinates.isEmpty) return ActivityLocation(name: name);

  final point = _parsePoint(coordinates);
  return ActivityLocation(
    name: name,
    latitude: point.$1,
    longitude: point.$2,
    coordinateInput: coordinates,
  );
}

(double, double) _parsePoint(String input) {
  final geo = RegExp(
    r'^geo:([+-]?(?:\d+(?:\.\d+)?|\.\d+)),'
    r'([+-]?(?:\d+(?:\.\d+)?|\.\d+))',
    caseSensitive: false,
  ).firstMatch(input);
  if (geo != null) {
    return _validated(double.parse(geo.group(1)!), double.parse(geo.group(2)!));
  }

  final pair = RegExp(
    r'^\s*([+-]?(?:\d+(?:\.\d+)?|\.\d+))'
    r'(?:\s*,\s*|\s+)'
    r'([+-]?(?:\d+(?:\.\d+)?|\.\d+))\s*$',
  ).firstMatch(input);
  if (pair != null) {
    return _validated(
      double.parse(pair.group(1)!),
      double.parse(pair.group(2)!),
    );
  }

  final plusCode = input.toUpperCase().replaceAll(' ', '');
  if (plusCode.contains('+')) return _decodeOpenLocationCode(plusCode);

  throw const LocationParseException(
    'Use “latitude, longitude”, a geo: URL, or a full Open Location Code.',
  );
}

(double, double) _validated(double latitude, double longitude) {
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw const LocationParseException(
      'Coordinates are outside the valid latitude/longitude range.',
    );
  }
  return (latitude, longitude);
}

(double, double) _decodeOpenLocationCode(String input) {
  const alphabet = '23456789CFGHJMPQRVWX';
  const separatorPosition = 8;
  final separator = input.indexOf('+');
  if (separator != separatorPosition) {
    throw const LocationParseException(
      'Short Open Location Codes need a nearby reference. Enter a full plus '
      'code with “+” in position 9.',
    );
  }

  final code = input.replaceAll('+', '').replaceAll('0', '');
  if (code.length < 2 ||
      code.length > 15 ||
      code.split('').any((character) => !alphabet.contains(character))) {
    throw const LocationParseException('That Open Location Code is invalid.');
  }

  final pairLength = code.length.clamp(0, 10);
  if (pairLength.isOdd) {
    throw const LocationParseException('That Open Location Code is invalid.');
  }

  var latitude = -90.0;
  var longitude = -180.0;
  var pairResolution = 20.0;
  var latitudeResolution = 20.0;
  var longitudeResolution = 20.0;
  for (var index = 0; index < pairLength; index += 2) {
    latitude += alphabet.indexOf(code[index]) * pairResolution;
    longitude += alphabet.indexOf(code[index + 1]) * pairResolution;
    latitudeResolution = pairResolution;
    longitudeResolution = pairResolution;
    pairResolution /= 20;
  }

  for (var index = 10; index < code.length; index++) {
    final digit = alphabet.indexOf(code[index]);
    latitudeResolution /= 5;
    longitudeResolution /= 4;
    latitude += (digit ~/ 4) * latitudeResolution;
    longitude += (digit % 4) * longitudeResolution;
  }

  final centerLatitude = latitude + latitudeResolution / 2;
  final centerLongitude = longitude + longitudeResolution / 2;
  return _validated(
    centerLatitude.clamp(-90, 90),
    centerLongitude.clamp(-180, 180),
  );
}
