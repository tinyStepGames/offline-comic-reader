import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_extraction_rule.dart';
import 'package:offline_comic_reader/services/rule_library.dart';
import 'package:offline_comic_reader/services/site_reading_settings.dart';
import 'package:offline_comic_reader/services/site_rule_store.dart';

SavedSiteRule site(SiteReadingSettings? reading) => SavedSiteRule(
  id: 'AAAAAAAAAAAAAAAAAAAAAA',
  name: 'History site',
  updatedAt: DateTime.utc(2026),
  rules: {
    'works': ListExtractionRule(
      pageUrl: 'https://example.com/list/',
      groupSelector: '.work',
      fields: defaultListFields(),
    ),
  },
  readingSettings: reading,
);

void main() {
  test('legacy chapter sites open chapter details before resuming', () {
    expect(
      ruleLibraryHistoryDestination(site(null)),
      RuleLibraryHistoryDestination.chapters,
    );
  });

  test('explicit chapter mode opens chapter details', () {
    expect(
      ruleLibraryHistoryDestination(
        site(const SiteReadingSettings(mode: SiteReadingMode.chapters)),
      ),
      RuleLibraryHistoryDestination.chapters,
    );
  });

  test('details mode opens work details before resuming', () {
    expect(
      ruleLibraryHistoryDestination(
        site(
          SiteReadingSettings(
            mode: SiteReadingMode.details,
            detailsRule: ListExtractionRule(
              pageUrl: 'https://example.com/work/',
              groupSelector: 'html',
              fields: defaultListFields(),
            ),
          ),
        ),
      ),
      RuleLibraryHistoryDestination.details,
    );
  });

  test('direct mode does not insert a details screen', () {
    expect(
      ruleLibraryHistoryDestination(
        site(const SiteReadingSettings(mode: SiteReadingMode.direct)),
      ),
      RuleLibraryHistoryDestination.reader,
    );
  });

  test('removed site does not create a fictitious details screen', () {
    expect(
      ruleLibraryHistoryDestination(null),
      RuleLibraryHistoryDestination.reader,
    );
  });
}
