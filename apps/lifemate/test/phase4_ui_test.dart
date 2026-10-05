import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/phase4_ui.dart';
void main(){testWidgets('phase4 hub exposes advisory privacy and non diagnosis copy',(tester)async{await tester.pumpWidget(const MaterialApp(home:Directionality(textDirection:TextDirection.rtl,child:Phase4Hub())));expect(find.text('راهنمای هوشمند'),findsOneWidget);expect(find.textContaining('تصمیم و اجرای تغییرها با خودت است'),findsOneWidget);expect(find.textContaining('نه تشخیص پزشکی'),findsOneWidget);expect(find.textContaining('خصوصی‌اند'),findsOneWidget);});}
