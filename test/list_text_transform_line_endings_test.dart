import 'package:flutter_test/flutter_test.dart';
import 'package:offline_comic_reader/services/list_text_transform.dart';

void main() {
  const input =
      'https://rawkuma.net/wp-content/uploads/2025/11/Mrs.-Akechi-320x320.jpg';

  test('末尾CRが付いた式とテンプレートでも元のURLを返す', () {
    expect(
      transformListText(input, pattern: '(.*)\r', replacement: '\$1\r'),
      input,
    );
  });

  test('先頭末尾のCR・LF・CRLFを無視する', () {
    for (final lineBreak in ['\r', '\n', '\r\n']) {
      expect(
        transformListText(
          input,
          pattern: '$lineBreak(.*)$lineBreak',
          replacement: '$lineBreak\$1$lineBreak',
        ),
        input,
      );
    }
  });

  test('サイズ除去の式にCRが付いていても正しく加工する', () {
    expect(
      transformListText(
        input,
        pattern:
            r'^(.*?)(?:-[0-9]+x[0-9]+)?(\.[^./?#]+(?:[?#].*)?)$'
            '\r',
        replacement: '\$1\$2\r',
      ),
      'https://rawkuma.net/wp-content/uploads/2025/11/Mrs.-Akechi.jpg',
    );
  });

  test('元からサイズ指定がないURLは保持する', () {
    const url = 'https://rawkuma.net/wp-content/uploads/2025/10/i495728.jpg';

    expect(
      transformListText(
        url,
        pattern:
            r'^(.*?)(?:-[0-9]+x[0-9]+)?(\.[^./?#]+(?:[?#].*)?)$'
            '\r\n',
        replacement: '\$1\$2\r\n',
      ),
      url,
    );
  });

  test('改行だけの式は未指定として扱う', () {
    expect(
      transformListText(input, pattern: '\r\n', replacement: '\r\n'),
      input,
    );
  });

  test('記号として記述された改行指定は保持する', () {
    expect(
      transformListText(
        'first\nsecond',
        pattern: r'^first\n(second)$',
        replacement: r'$1',
      ),
      'second',
    );
  });

  test('式の途中にある実際の改行は保持する', () {
    expect(
      transformListText(
        'first\nsecond',
        pattern: '^first\n(second)\$',
        replacement: r'$1',
      ),
      'second',
    );
  });

  test('意図した先頭スペースを除去しない', () {
    expect(
      () => transformListText('abc', pattern: r'^ abc$', replacement: r'$0'),
      throwsFormatException,
    );
  });
}
