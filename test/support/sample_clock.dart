import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';

/// Frozen instant shared by repository tests and the sample groups they load.
final sampleNow = DateTime(2026, 10, 27, 12);

FakeDatabase loadSampleDatabase() => buildSampleDatabase(now: sampleNow);

FixedClock loadSampleClock() => FixedClock(sampleNow);
