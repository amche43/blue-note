import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); sqfliteFfiInit();
  
  testWidgets('Every formula and linked knowledge reference is valid', (tester) async {
    final raw=jsonDecode((await tester.runAsync(() => rootBundle.loadString('assets/lessons.json')))!) as Map<String,dynamic>;
    for(final lesson in raw['lessons'] as List){
      final concepts=(lesson['concepts'] as List).map((c)=>c['id']).toSet();
      for(final step in lesson['steps'] as List){
        for(final match in RegExp(r'\[\[([^|]+)\|([^\]]+)\]\]').allMatches(step['text'] as String)){
          expect(concepts.contains(match.group(1)),isTrue,reason:lesson['id'] as String);
        }
      }
      for(final node in [lesson,...lesson['steps'],...lesson['concepts'],...lesson['variants']]){
        if(node['formula']!=null){
          bool failed=false;
          await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(scrollDirection:Axis.horizontal,child:
            Math.tex(node['formula'] as String,onErrorFallback:(_){failed=true;return const Text('invalid');})))));
          await tester.pumpAndSettle();expect(failed,isFalse,reason:node['formula'] as String);expect(tester.takeException(),isNull);
        }
      }
    }
  });
}
