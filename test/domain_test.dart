import 'package:flutter_test/flutter_test.dart';
import 'package:blue_note/domain.dart';

StudyEvent event(String id, String type, Json payload, {int at = 1000}) => StudyEvent(
  id: id.padLeft(32,'0'), lessonId: 'math-symmetry', type: type, at: at, payload: payload);
Json attempt({bool assisted=false, bool correct=true, String rating='good'}) => {
  'rating':rating,'assisted':assisted,'correct':correct,'variantId':'sym-near','reason':'没想到用',
};
void main() {
  test('Unicode notes survive portable backup round-trip', () {
    final note=event('a','note',{'text':'先互换，再相加。π/4\n条件不能少。'});
    expect(decodeBackup(encodeBackup([note])).single.payload,note.payload);
  });
  test('Looking at a hint is never an independent completion', () {
    final p=Progress.fromEvents([event('a','attempt',attempt(assisted:true))]);
    expect(p.independent,0); expect(p.status,'借助提示完成');
    expect(p.due,DateTime.fromMillisecondsSinceEpoch(1000).add(const Duration(days:1)));
  });
  test('Wrong answers schedule a near review and reset success streak', () {
    final p=Progress.fromEvents([event('a','attempt',attempt()),event('b','attempt',attempt(correct:false),at:2000)]);
    expect(p.independent,0); expect(p.status,'需要再练');
    expect(p.due,DateTime.fromMillisecondsSinceEpoch(2000).add(const Duration(minutes:10)));
  });
  test('Merge order does not change the visible note or erase history', () {
    final a=event('a','note',{'text':'旧总结'}), b=event('b','note',{'text':'新总结'});
    expect(Progress.fromEvents([b,a]).note,'新总结');
    expect(Progress.fromEvents([a,b]).noteHistory.length,2);
  });
  test('Unsupported versions and malformed grades are rejected', () {
    expect(() => decodeBackup('{"schemaVersion":99,"events":[]}'),throwsFormatException);
    expect(() => decodeBackup(encodeBackup([event('a','attempt',{'rating':'good'})])),throwsFormatException);
  });
}
