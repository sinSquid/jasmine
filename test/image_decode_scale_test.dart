import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/image_decode_scale.dart';

void main() {
  test(
      'tiny zooms stay at viewport resolution and larger zooms use bounded tiers',
      () {
    expect(imageDecodeScale(1.05), 1);
    expect(imageDecodeScale(1.25), 1);
    expect(imageDecodeScale(1.3), 2);
    expect(imageDecodeScale(2), 2);
    expect(imageDecodeScale(2.1), 3);
    expect(imageDecodeScale(3.5), 4);
    expect(imageDecodeScale(100), 4);
    expect(imageDecodeScale(double.nan), 1);
    expect(imageDecodeScale(double.infinity), 1);
  });
}
