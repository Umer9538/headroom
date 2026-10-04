import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

/// The Swift core's `StatisticsTests`.
void main() {
  test('median of odd and even counts', () {
    expect(Statistics.median([3, 1, 2]), 2);
    expect(Statistics.median([4, 1, 3, 2]), 2.5);
    expect(Statistics.median([7]), 7);
    expect(() => Statistics.median([]), throwsArgumentError);
  });

  test('bootstrap interval brackets the median', () {
    const samples = <double>[55, 57, 58, 58.5, 59, 59.2, 60, 60.5, 61, 63];
    final interval = Statistics.bootstrapMedianInterval(samples);
    final median = Statistics.median(samples);
    expect(interval.low, lessThanOrEqualTo(median));
    expect(median, lessThanOrEqualTo(interval.high));
    expect(interval.low, greaterThanOrEqualTo(55));
    expect(interval.high, lessThanOrEqualTo(63));
  });

  test('bootstrap is deterministic for a given seed', () {
    const samples = <double>[1, 2, 3, 4, 5, 6, 7];
    final first = Statistics.bootstrapMedianInterval(samples);
    final second = Statistics.bootstrapMedianInterval(samples);
    expect(first, second);
    final other = Statistics.bootstrapMedianInterval(samples, seed: 7);
    expect(other.low, lessThanOrEqualTo(other.high));
  });

  test('constant samples give a degenerate interval', () {
    final interval = Statistics.bootstrapMedianInterval([42, 42, 42, 42]);
    expect(interval.low, 42);
    expect(interval.high, 42);
    expect(Statistics.bootstrapMedianInterval([9]), (low: 9.0, high: 9.0));
  });

  test('SplitMix64 matches the reference sequence', () {
    // First outputs of Vigna's reference implementation for seed 0.
    final generator = SplitMix64(0);
    expect(generator.next(), 0xE220A8397B1DCDAF);
    expect(generator.next(), 0x6E789E6AA1B965F4);
  });

  test('indices stay inside the bound and use every value', () {
    final generator = SplitMix64(0x4845414452_4F4F4D);
    final seen = <int>{};
    for (var i = 0; i < 10000; i++) {
      final index = generator.nextIndex(7);
      expect(index, inInclusiveRange(0, 6));
      seen.add(index);
    }
    expect(seen.length, 7);
    expect(() => generator.nextIndex(0), throwsArgumentError);
  });
}
