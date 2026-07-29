import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genericagentmobile/main.dart';

void main() {
  testWidgets('GenericAgent 应用正常启动，显示聊天界面', (WidgetTester tester) async {
    // Build the GenericAgent app and trigger a frame.
    await tester.pumpWidget(const GenericAgentApp());

    // 验证 AppBar 标题存在
    expect(find.text('GenericAgent'), findsOneWidget);

    // 验证输入框存在
    expect(find.byType(TextField), findsOneWidget);

    // 验证发送按钮存在
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}