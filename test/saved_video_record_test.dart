import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/saved_video_record.dart';
import '../lib/services/video_download_engine.dart';
import '../lib/services/video_progress.dart';

const siteId = 'abcdefghijklmnopqrstuv';

SavedVideoRecord makeRecord({
  String site = siteId,
  String chapter = 'https://example.com/show/episode-1',
}) => SavedVideoRecord.create(
  siteId: site,
  siteName: 'Test site',
  workUrl: 'https://example.com/show/',
  chapterUrl: chapter,
  title: 'Episode 1',
  workTitle: 'Test work',
);

void main() {
  test('record round trip preserves identity and metadata', () {
    final record = makeRecord();
    final restored = SavedVideoRecord.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(record.toJson())) as Map),
    );

    expect(restored.identity, record.identity);
    expect(restored.id, record.id);
    expect(restored.workTitle, 'Test work');
    expect(restored.chapter.title, 'Episode 1');
  });

  test('site and episode query are part of identity', () {
    expect(
      makeRecord(site: 'ABCDEFGHIJKLMNOPQRSTUV').id,
      isNot(makeRecord().id),
    );
    expect(
      makeRecord(chapter: 'https://example.com/show/episode-1?q=1').id,
      isNot(makeRecord(chapter: 'https://example.com/show/episode-1?q=2').id),
    );
  });

  test('fragments do not create duplicate packages', () {
    expect(
      makeRecord(chapter: 'https://example.com/show/episode-1#player').id,
      makeRecord().id,
    );
  });

  test('offline and online use the same progress key', () {
    final record = makeRecord();

    expect(
      record.progressKey,
      ruleVideoProgressKey(
        siteId: siteId,
        chapterUrl: record.chapter.url.toString(),
      ),
    );
  });

  test('cross origin episode is rejected', () {
    expect(
      () => makeRecord(chapter: 'https://other.example.com/episode-1'),
      throwsFormatException,
    );
  });

  test('tampered chapter identifiers are rejected', () {
    final data = makeRecord().toJson();
    final chapter = Map<String, dynamic>.from(data['chapter'] as Map);
    chapter['storageId'] = 'custom-tampered';
    data['chapter'] = chapter;

    expect(() => SavedVideoRecord.fromJson(data), throwsFormatException);
  });

  test('package identity must match its metadata', () {
    final record = makeRecord();

    final valid = SavedVideoPackage(
      id: record.id,
      title: record.chapter.title,
      entry: 'video.mp4',
      files: const {},
      metadata: record.toJson(),
    );
    expect(SavedVideoRecord.forPackage(valid).id, record.id);

    final invalid = SavedVideoPackage(
      id: VideoDownloadRepository.idFor('other'),
      title: record.chapter.title,
      entry: 'video.mp4',
      files: const {},
      metadata: record.toJson(),
    );
    expect(() => SavedVideoRecord.forPackage(invalid), throwsFormatException);
  });

  test('invalid metadata version is rejected', () {
    final data = makeRecord().toJson();
    data['version'] = 9;
    expect(() => SavedVideoRecord.fromJson(data), throwsFormatException);
  });

  test('size labels use binary units', () {
    expect(savedVideoSize(123), '123 B');
    expect(savedVideoSize(1024), '1.0 KiB');
    expect(savedVideoSize(1024 * 1024), '1.0 MiB');
    expect(savedVideoSize(1024 * 1024 * 1024), '1.00 GiB');
  });
}
