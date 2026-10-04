// Flutter's animation library also has an `Interval`; headroom's is the one
// used here.
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/services.dart';
import 'package:headroom/headroom.dart';

void main() => runApp(const HeadroomExampleApp());

/// One Probe button, a report card, an estimate table for four model sizes,
/// and Copy JSON for pasting a phone's result back into the calibration.
class HeadroomExampleApp extends StatelessWidget {
  const HeadroomExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Headroom',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const ProbePage(),
  );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  ProbeReport? _report;
  String? _error;
  bool _running = false;

  Future<void> _probe() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report = await Headroom.probe();
      setState(() => _report = report);
    } on ProbeCancelledException {
      // The button was pressed again; nothing to show.
    } on HeadroomException catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copyJson() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toJsonString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report JSON copied')));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Headroom')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A two-second probe of this device\'s memory bandwidth, and what '
            'it means for a model of a given size. Every figure says whether '
            'it was measured here or calibrated elsewhere.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? Headroom.cancel : _probe,
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(_running ? 'Cancel' : 'Probe'),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 16),
            ReportCard(report: report),
            const SizedBox(height: 16),
            EstimateTable(report: report),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _copyJson,
              icon: const Icon(Icons.copy),
              label: const Text('Copy JSON'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ceilings with their confidence intervals and basis, then the conditions
/// the probe ran under.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.report});

  final ProbeReport report;

  @override
  Widget build(BuildContext context) {
    final device = report.device;
    final gpu = report.gpu;
    final cpu = report.cpu;
    final memory = report.memory;
    return _Card(
      children: [
        Text(
          '${device.identifier} · ${device.platform.jsonName} '
          '${device.osVersion} (${device.osBuild})'
          '${device.chip == null ? '' : ' · ${device.chip}'}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (gpu != null)
          _CeilingRow(title: 'GPU ceiling (Metal triad)', figure: gpu.triad)
        else
          const _LabelledRow(
            title: 'GPU ceiling',
            value: 'not measured',
            basis: Basis.unknown,
          ),
        const SizedBox(height: 8),
        if (cpu != null)
          _CeilingRow(
            title: 'CPU triad, ${cpu.threads} threads'
                '${cpu.attempts.length > 1 ? ' (best of ${cpu.attempts.length})' : ''}',
            figure: cpu.triad,
          )
        else
          const _LabelledRow(
            title: 'CPU triad',
            value: 'not measured',
            basis: Basis.unknown,
          ),
        const Divider(height: 24),
        _LabelledRow(
          title: 'Thermal',
          value: report.conditions.thermalState.name +
              (report.conditions.platformThermalStatus == null
                  ? ''
                  : ' (${report.conditions.platformThermalStatus})'),
          basis: Basis.measured,
        ),
        _LabelledRow(
          title: 'Power',
          value: _powerDescription(report.conditions),
          basis: Basis.measured,
        ),
        _LabelledRow(
          title: 'Memory',
          value: '${(memory.physicalBytes / 1e9).toStringAsFixed(2)} GB physical',
          basis: Basis.measured,
        ),
        _LabelledRow(
          title: 'Available',
          value: '${(memory.availableBytes.value / 1e9).toStringAsFixed(2)} GB'
              '${memory.lowMemory == true ? ', low memory' : ''}',
          basis: memory.availableBytes.basis,
        ),
        for (final warning in report.warnings) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _powerDescription(Conditions conditions) {
    final buffer = StringBuffer(conditions.powerSource.name);
    final level = conditions.batteryLevel;
    if (level != null) buffer.write(', ${(level * 100).round()}%');
    if (conditions.isLowPowerModeEnabled) buffer.write(', low power mode');
    return buffer.toString();
  }
}

/// The same four rows as the Swift demo: one verified model and three size
/// classes known only by file size, at 1024 tokens of context.
class EstimateTable extends StatelessWidget {
  EstimateTable({super.key, required this.report});

  final ProbeReport report;

  static const int contextTokens = 1024;

  final List<ModelSpec> models = [
    ModelSpec.tinyLlama1_1BQ4_0,
    ModelSpec.fromGgufBytes(name: '1.1 GB model', ggufBytes: 1100000000),
    ModelSpec.fromGgufBytes(name: '2.2 GB model', ggufBytes: 2200000000),
    ModelSpec.fromGgufBytes(name: '4.4 GB model', ggufBytes: 4400000000),
  ];

  @override
  Widget build(BuildContext context) {
    final estimates = [
      for (final model in models)
        report.estimate(model, contextTokens: contextTokens),
    ];
    final notes = {for (final estimate in estimates) ...estimate.notes}.toList()
      ..sort();
    return _Card(
      children: [
        Text(
          'Decode estimate at $contextTokens tokens of context',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final estimate in estimates) ...[
          Row(
            children: [
              Expanded(child: Text(estimate.model.name)),
              _FitTag(fit: estimate.fit),
            ],
          ),
          _IntervalRow(title: 'peak', interval: estimate.peak),
          if (estimate.sustained case final sustained?)
            _IntervalRow(title: 'sustained', interval: sustained),
          const Divider(height: 16),
        ],
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              note,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _CeilingRow extends StatelessWidget {
  const _CeilingRow({required this.title, required this.figure});

  final String title;
  final BandwidthFigure figure;

  @override
  Widget build(BuildContext context) {
    final ci = figure.medianCI95GBps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${figure.medianGBps.value.toStringAsFixed(1)} GB/s',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '95% CI ${ci.low.toStringAsFixed(1)}–${ci.high.toStringAsFixed(1)}, '
                'best ${figure.bestGBps.value.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        BasisTag(basis: figure.medianGBps.basis),
      ],
    );
  }
}

class _LabelledRow extends StatelessWidget {
  const _LabelledRow({
    required this.title,
    required this.value,
    required this.basis,
  });

  final String title;
  final String value;
  final Basis basis;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(value),
        const SizedBox(width: 8),
        BasisTag(basis: basis),
      ],
    ),
  );
}

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({required this.title, required this.interval});

  final String title;
  final Interval interval;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          interval.isKnown
              ? '${interval.low.toStringAsFixed(0)}–'
                    '${interval.high.toStringAsFixed(0)} tok/s'
              : 'unknown',
        ),
        const SizedBox(width: 8),
        BasisTag(basis: interval.basis),
      ],
    ),
  );
}

/// The basis is never implied; it is printed next to every figure.
class BasisTag extends StatelessWidget {
  const BasisTag({super.key, required this.basis});

  final Basis basis;

  @override
  Widget build(BuildContext context) {
    final color = switch (basis) {
      MeasuredBasis() => Colors.green,
      CalibratedBasis() => Colors.blue,
      UnknownBasis() => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        basis.toString(),
        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color),
      ),
    );
  }
}

class _FitTag extends StatelessWidget {
  const _FitTag({required this.fit});

  final MemoryFit fit;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (fit.verdict) {
      FitsVerdict(:final marginMB) => (
        'fits, ${marginMB.toStringAsFixed(0)} MB spare',
        Colors.green,
      ),
      TightVerdict(:final marginMB) => (
        'tight, ${marginMB.toStringAsFixed(0)} MB spare',
        Colors.orange,
      ),
      DoesNotFitVerdict(:final shortfallMB) => (
        '${shortfallMB.toStringAsFixed(0)} MB short',
        Colors.red,
      ),
    };
    final unknown = fit.basis == Basis.unknown;
    return Text(
      unknown ? '$text (unknown)' : text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: unknown ? Colors.orange : color,
      ),
    );
  }
}
