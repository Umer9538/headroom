import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/headroom.dart';

import 'fixtures.dart';

/// The Dart side of the `headroom/probe` channel, against a mocked native
/// side that answers with the committed M1 run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;

  final calls = <MethodCall>[];

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(Headroom.channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(Headroom.channel, null));

  test('probe sends the options and decodes the report', () async {
    answerWith((call) async => Fixtures.m1Run1Json());
    final report = await Headroom.probe(
      options: const ProbeOptions(cpuThreads: 4, runsGPUProbe: false),
    );
    expect(calls.single.method, 'probe');
    expect(calls.single.arguments, {
      'gpuArrayBytes': 128 << 20,
      'gpuWarmupIterations': 1,
      'gpuTimedIterations': 10,
      'cpuArrayBytes': 64 << 20,
      'cpuThreads': 4,
      'cpuWarmupIterations': 1,
      'cpuTimedIterations': 7,
      'runsGPUProbe': false,
      'runsCPUProbe': true,
    });
    expect(report.device.identifier, 'MacBookPro17,1');
    expect(report.ceilingGBps?.value, 56.33319137456001);
    expect(Calibration.shipped, isNotNull);
    // The calibration was loaded by the probe, so estimating needs no await.
    final estimate = report.estimate(
      ModelSpec.tinyLlama1_1BQ4_0,
      contextTokens: 1024,
    );
    expect(estimate.peak.basis, const Basis.calibrated(devices: 1));
    expect(Headroom.isProbing, isFalse);
  });

  test('invalid options are rejected before anything runs', () async {
    answerWith((call) async => Fixtures.m1Run1Json());
    await expectLater(
      Headroom.probe(options: const ProbeOptions(gpuArrayBytes: 4096 + 16)),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('a cancel before the native call starts never starts it', () async {
    answerWith((call) async => Fixtures.m1Run1Json());
    final pending = Headroom.probe();
    // Listen before cancelling, or the error lands with nobody waiting.
    final outcome = expectLater(pending, throwsA(isA<ProbeCancelledException>()));
    expect(Headroom.isProbing, isTrue);
    await Headroom.cancel();
    await outcome;
    expect(Headroom.isProbing, isFalse);
    expect([for (final call in calls) call.method], isNot(contains('probe')));
  });

  test('a native cancellation surfaces as ProbeCancelledException', () async {
    final native = Completer<String>();
    answerWith((call) {
      if (call.method == 'cancel') {
        native.completeError(
          PlatformException(code: 'cancelled', message: 'stopped'),
        );
        return Future.value();
      }
      return native.future;
    });
    final pending = Headroom.probe();
    final outcome = expectLater(pending, throwsA(isA<ProbeCancelledException>()));
    while (!calls.any((call) => call.method == 'probe')) {
      await Future<void>.delayed(Duration.zero);
    }
    await Headroom.cancel();
    await outcome;
    expect(Headroom.isProbing, isFalse);
    expect([for (final call in calls) call.method], ['probe', 'cancel']);
  });

  test('cancel without a running probe does nothing', () async {
    answerWith((call) async => null);
    await Headroom.cancel();
    expect(calls, isEmpty);
  });

  test('native failures become HeadroomException with the platform code', () async {
    answerWith((call) async {
      throw PlatformException(code: 'invalidOptions', message: 'bad');
    });
    await expectLater(
      Headroom.probe(),
      throwsA(
        isA<HeadroomException>()
            .having((e) => e.code, 'code', 'invalidOptions')
            .having((e) => e.message, 'message', 'bad'),
      ),
    );
  });

  test('a second probe while one runs is refused as busy', () async {
    answerWith((call) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return Fixtures.m1Run1Json();
    });
    final first = Headroom.probe();
    await expectLater(
      Headroom.probe(),
      throwsA(isA<HeadroomException>().having((e) => e.code, 'code', 'busy')),
    );
    await first;
    expect(calls.length, 1);
  });

  test('a malformed report is reported, not crashed on', () async {
    answerWith((call) async => '{"schemaVersion": 1}');
    await expectLater(
      Headroom.probe(),
      throwsA(
        isA<HeadroomException>().having((e) => e.code, 'code', 'malformedReport'),
      ),
    );
  });

  test('a platform without the plugin is unsupported', () async {
    // No handler registered: the channel raises MissingPluginException.
    await expectLater(
      Headroom.probe(),
      throwsA(
        isA<HeadroomException>().having((e) => e.code, 'code', 'unsupported'),
      ),
    );
  });
}
