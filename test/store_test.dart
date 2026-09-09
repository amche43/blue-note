import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Notes persist across reopen, restore is idempotent, conflict rolls back', () async {
    final dir=await Directory.systemTemp.createTemp('blue-note-test-');
    final path='${dir.path}/study.db';
    final first=await StudyStore.open(factory:databaseFactoryFfi,path:path);
    await first.note('math-symmetry','我的对称换元总结');
    final backup=first.backup();
    await first.db.close();first.dispose();
    final second=await StudyStore.open(factory:databaseFactoryFfi,path:path);
    expect(second.progress('math-symmetry').note,'我的对称换元总结');
    expect(await second.restore(backup),0);
    final old=second.events.single;
    final valid=StudyEvent(id:newId(),lessonId:'math-point-identity',type:'note',at:1000,payload:{'text':'不应被提交'});
    final conflict=StudyEvent(id:old.id,lessonId:old.lessonId,type:old.type,at:old.at,payload:{'text':'冲突'});
    await expectLater(second.merge([valid,conflict]),throwsFormatException);
    await second.refresh(); expect(second.events.length,1);
    expect(second.progress('math-symmetry').note,'我的对称换元总结');
    await second.db.close();second.dispose();
    // The test only removes the exact scratch directory created above.
    await dir.delete(recursive:true);
  });
}
