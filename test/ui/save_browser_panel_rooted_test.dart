import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/ui/save_browser_panel.dart';

void main() {
  test('SaveBrowserPanel has rootFolderId prop', () {
    const panel = SaveBrowserPanel(rootFolderId: 'test');
    expect(panel.rootFolderId, 'test');
  });

  test('SaveBrowserPanel rootFolderId defaults to null', () {
    const panel = SaveBrowserPanel();
    expect(panel.rootFolderId, isNull);
  });
}
