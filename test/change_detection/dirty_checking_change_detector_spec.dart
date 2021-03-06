library dirty_chekcing_change_detector_spec;

import '../_specs.dart';
import 'package:angular/change_detection/change_detection.dart';
import 'package:angular/change_detection/dirty_checking_change_detector.dart';
import 'dart:collection';
import 'dart:math';

void main() {
  describe('DirtyCheckingChangeDetector', () {
    DirtyCheckingChangeDetector<String> detector;
    GetterCache getterCache;

    beforeEach(() {
      getterCache = new GetterCache({
        "first": (o) => o.first,
        "age": (o) => o.age
      });
      detector = new DirtyCheckingChangeDetector<String>(getterCache);
    });

    describe('object field', () {
      it('should detect nothing', () {
        var changes = detector.collectChanges();
        expect(changes.moveNext()).toEqual(false);
      });

      it('should detect field changes', () {
        var user = new _User('', '');
        Iterator changeIterator;

        detector..watch(user, 'first', null)
                ..watch(user, 'last', null)
                ..collectChanges(); // throw away first set

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);
        user..first = 'misko'
            ..last = 'hevery';

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('misko');
        expect(changeIterator.current.previousValue).toEqual('');
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('hevery');
        expect(changeIterator.current.previousValue).toEqual('');
        expect(changeIterator.moveNext()).toEqual(false);

        // force different instance
        user.first = 'mis';
        user.first += 'ko';

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.last = 'Hevery';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('Hevery');
        expect(changeIterator.current.previousValue).toEqual('hevery');
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should ignore NaN != NaN', () {
        var user = new _User();
        user.age = double.NAN;
        detector..watch(user, 'age', null)..collectChanges(); // throw away first set

        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.age = 123;
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual(123);
        expect(changeIterator.current.previousValue.isNaN).toEqual(true);
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should treat map field dereference as []', () {
        var obj = {'name':'misko'};
        detector.watch(obj, 'name', null);
        detector.collectChanges(); // throw away first set

        obj['name'] = 'Misko';
        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('Misko');
        expect(changeIterator.current.previousValue).toEqual('misko');
      });
    });

    describe('insertions / removals', () {
      it('should insert at the end of list', () {
        var obj = {};
        var a = detector.watch(obj, 'a', 'a');
        var b = detector.watch(obj, 'b', 'b');

        obj['a'] = obj['b'] = 1;
        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('a');
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('b');
        expect(changeIterator.moveNext()).toEqual(false);

        obj['a'] = obj['b'] = 2;
        a.remove();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('b');
        expect(changeIterator.moveNext()).toEqual(false);

        obj['a'] = obj['b'] = 3;
        b.remove();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should remove all watches in group and group\'s children', () {
        var obj = {};
        detector.watch(obj, 'a', '0a');
        var child1a = detector.newGroup();
        var child1b = detector.newGroup();
        var child2 = child1a.newGroup();
        child1a.watch(obj,'a', '1a');
        child1b.watch(obj,'a', '1b');
        detector.watch(obj, 'a', '0A');
        child1a.watch(obj,'a', '1A');
        child2.watch(obj,'a', '2A');

        var iterator;
        obj['a'] = 1;
        expect(detector.collectChanges(),
            toEqualChanges(['0a', '0A', '1a', '1A', '2A', '1b']));

        obj['a'] = 2;
        child1a.remove(); // should also remove child2
        expect(detector.collectChanges(), toEqualChanges(['0a', '0A', '1b']));
      });

      it('should add watches within its own group', () {
        var obj = {};
        var ra = detector.watch(obj, 'a', 'a');
        var child = detector.newGroup();
        var cb = child.watch(obj,'b', 'b');
        var iterotar;

        obj['a'] = obj['b'] = 1;
        expect(detector.collectChanges(), toEqualChanges(['a', 'b']));

        obj['a'] = obj['b'] = 2;
        ra.remove();
        expect(detector.collectChanges(), toEqualChanges(['b']));

        obj['a'] = obj['b'] = 3;
        cb.remove();
        expect(detector.collectChanges(), toEqualChanges([]));

        // TODO: add them back in wrong order, assert events in right order
        cb = child.watch(obj,'b', 'b');
        ra = detector.watch(obj, 'a', 'a');
        obj['a'] = obj['b'] = 4;
        expect(detector.collectChanges(), toEqualChanges(['a', 'b']));
      });

      it('should properly add children', () {
        var a = detector.newGroup();
        var aChild = a.newGroup();
        var b = detector.newGroup();
        expect(detector.collectChanges).not.toThrow();
      });

      it('should properly disconnect group in case watch is removed in disconected group', () {
        var map = {};
        var detector0 = new DirtyCheckingChangeDetector<String>(getterCache);
          var detector1 = detector0.newGroup();
            var detector2 = detector1.newGroup();
            var watch2 = detector2.watch(map, 'f1', null);
          var detector3 = detector0.newGroup();
          detector1.remove();
            watch2.remove(); // removing a dead record
          detector3.watch(map, 'f2', null);
      });

      it('should find random bugs', () {
        List detectors;
        List records;
        List steps;
        var field = 'someField';
        step(text) {
          //print(text);
          steps.add(text);
        }
        Map map = {};
        var random = new Random();
        try {
          for (var i = 0; i < 100000; i++) {
            if (i % 50 == 0) {
              //print(steps);
              //print('===================================');
              records = [];
              steps = [];
              detectors = [new DirtyCheckingChangeDetector<String>(getterCache)];
            }
            switch (random.nextInt(4)) {
              case 0: // new child detector
                if (detectors.length > 10) break;
                var index = random.nextInt(detectors.length);
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].newGroup()');
                var child = detector.newGroup();
                detectors.add(child);
                break;
              case 1: // add watch
                var index = random.nextInt(detectors.length);
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].watch(map, field, null)');
                WatchRecord record = detector.watch(map, field, null);
                records.add(record);
                break;
              case 2: // destroy watch group
                if (detectors.length == 1) break;
                var index = random.nextInt(detectors.length - 1) + 1;
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].remove()');
                detector.remove();
                detectors = detectors
                    .where((s) => s.isAttached)
                    .toList();
                break;
              case 3: // remove watch on watch group
                if (records.length == 0) break;
                var index = random.nextInt(records.length);
                WatchRecord record = records.removeAt(index);
                step('records.removeAt($index).remove()');
                record.remove();
                break;
            }
          }
        } catch(e) {
          print(steps);
          rethrow;
        }
      });

    });

    describe('list watching', () {
      it('should detect changes in list', () {
        var list = [];
        var record = detector.watch(list, null, 'handler');
        expect(detector.collectChanges().moveNext()).toEqual(false);
        var iterator;

        list.add('a');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a[null -> 0]'],
            additions: ['a[null -> 0]'],
            moves: [],
            removals: []));

        list.add('b');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'b[null -> 1]'],
            additions: ['b[null -> 1]'],
            moves: [],
            removals: []));

        list.add('c');
        list.add('d');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'b', 'c[null -> 2]', 'd[null -> 3]'],
            additions: ['c[null -> 2]', 'd[null -> 3]'],
            moves: [],
            removals: []));

        list.remove('c');
        expect(list).toEqual(['a', 'b', 'd']);
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'b', 'd[3 -> 2]'],
            additions: [],
            moves: ['d[3 -> 2]'],
            removals: ['c[2 -> null]']));

        list.clear();
        list.addAll(['d', 'c', 'b', 'a']);
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['d[2 -> 0]', 'c[null -> 1]', 'b[1 -> 2]', 'a[0 -> 3]'],
            additions: ['c[null -> 1]'],
            moves: ['d[2 -> 0]', 'b[1 -> 2]', 'a[0 -> 3]'],
            removals: []));
      });

      it('should test string by value rather than by reference', () {
        var list = ['a', 'boo'];
        detector..watch(list, null, null)..collectChanges();

        list[1] = 'b' + 'oo';

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should ignore [NaN] != [NaN]', () {
        var list = [double.NAN];
        var record = detector..watch(list, null, null)..collectChanges();

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should remove and add same item', () {
        var list = ['a', 'b', 'c'];
        var record = detector.watch(list, null, 'handler');
        var iterator;
        detector.collectChanges();

        list.remove('b');
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'c[2 -> 1]'],
            additions: [],
            moves: ['c[2 -> 1]'],
            removals: ['b[1 -> null]']));

        list.insert(1, 'b');
        expect(list).toEqual(['a', 'b', 'c']);
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'b[null -> 1]', 'c[1 -> 2]'],
            additions: ['b[null -> 1]'],
            moves: ['c[1 -> 2]'],
            removals: []));
      });

      it('should support duplicates', () {
        var list = ['a', 'a', 'a', 'b', 'b'];
        var record = detector.watch(list, null, 'handler');
        detector.collectChanges();

        list.removeAt(0);
        var iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['a', 'a', 'b[3 -> 2]', 'b[4 -> 3]'],
            additions: [],
            moves: ['b[3 -> 2]', 'b[4 -> 3]'],
            removals: ['a[2 -> null]']));
      });


      it('should support insertions/moves', () {
        var list = ['a', 'a', 'b', 'b'];
        var record = detector.watch(list, null, 'handler');
        var iterator;
        detector.collectChanges();
        list.insert(0, 'b');
        expect(list).toEqual(['b', 'a', 'a', 'b', 'b']);
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['b[2 -> 0]', 'a[0 -> 1]', 'a[1 -> 2]', 'b', 'b[null -> 4]'],
            additions: ['b[null -> 4]'],
            moves: ['b[2 -> 0]', 'a[0 -> 1]', 'a[1 -> 2]'],
            removals: []));
      });

      it('should support UnmodifiableListView', () {
        var hiddenList = [1];
        var list = new UnmodifiableListView(hiddenList);
        var record = detector.watch(list, null, 'handler');
        var iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['1[null -> 0]'],
            additions: ['1[null -> 0]'],
            moves: [],
            removals: []));

        // assert no changes detected
        expect(detector.collectChanges().moveNext()).toEqual(false);

        // change the hiddenList normally this should trigger change detection
        // but because we are wrapped in UnmodifiableListView we see nothing.
        hiddenList[0] = 2;
        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should bug', () {
        var list = [1, 2, 3, 4];
        var record = detector.watch(list, null, 'handler');
        var iterator;

        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['1[null -> 0]', '2[null -> 1]', '3[null -> 2]', '4[null -> 3]'],
            additions: ['1[null -> 0]', '2[null -> 1]', '3[null -> 2]', '4[null -> 3]'],
            moves: [],
            removals: []));
        detector.collectChanges();

        list.removeRange(0, 1);
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['2[1 -> 0]', '3[2 -> 1]', '4[3 -> 2]'],
            additions: [],
            moves: ['2[1 -> 0]', '3[2 -> 1]', '4[3 -> 2]'],
            removals: ['1[0 -> null]']));

        list.insert(0, 1);
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['1[null -> 0]', '2[0 -> 1]', '3[1 -> 2]', '4[2 -> 3]'],
            additions: ['1[null -> 0]'],
            moves: ['2[0 -> 1]', '3[1 -> 2]', '4[2 -> 3]'],
            removals: []));
      });

      it('should properly support objects with equality', () {
        FooBar.fooIds = 0;
        var list = [new FooBar('a', 'a'), new FooBar('a', 'a')];
        var record = detector.watch(list, null, 'handler');
        var iterator;

        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['(0)a-a[null -> 0]', '(1)a-a[null -> 1]'],
            additions: ['(0)a-a[null -> 0]', '(1)a-a[null -> 1]'],
            moves: [],
            removals: []));
        detector.collectChanges();

        list.removeRange(0, 1);
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['(1)a-a[1 -> 0]'],
            additions: [],
            moves: ['(1)a-a[1 -> 0]'],
            removals: ['(0)a-a[0 -> null]']));

        list.insert(0, new FooBar('a', 'a'));
        iterator = detector.collectChanges()..moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            collection: ['(2)a-a[null -> 0]', '(1)a-a[0 -> 1]'],
            additions: ['(2)a-a[null -> 0]'],
            moves: ['(1)a-a[0 -> 1]'],
            removals: []));
      });
    });

    describe('map watching', () {
      it('should do basic map watching', () {
        var map = {};
        var record = detector.watch(map, null, 'handler');
        expect(detector.collectChanges().moveNext()).toEqual(false);

        var changeIterator;
        map['a'] = 'A';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            map: ['a[null -> A]'],
            additions: ['a[null -> A]'],
            changes: [],
            removals: []));

        map['b'] = 'B';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            map: ['a', 'b[null -> B]'],
            additions: ['b[null -> B]'],
            changes: [],
            removals: []));

        map['b'] = 'BB';
        map['d'] = 'D';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            map: ['a', 'b[B -> BB]', 'd[null -> D]'],
            additions: ['d[null -> D]'],
            changes: ['b[B -> BB]'],
            removals: []));

        map.remove('b');
        expect(map).toEqual({'a': 'A', 'd':'D'});
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            map: ['a', 'd'],
            additions: [],
            changes: [],
            removals: ['b[BB -> null]']));

        map.clear();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            map: [],
            additions: [],
            changes: [],
            removals: ['a[A -> null]', 'd[D -> null]']));
      });

      it('should test string keys by value rather than by reference', () {
        var map = {'foo': 0};
        detector..watch(map, null, null)..collectChanges();

        map['f' + 'oo'] = 0;

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should test string values by value rather than by reference', () {
        var map = {'foo': 'bar'};
        detector..watch(map, null, null)..collectChanges();

        map['foo'] = 'b' + 'ar';

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should not see a NaN value as a change', () {
        var map = {'foo': double.NAN};
        var record = detector..watch(map, null, null)..collectChanges();

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });
    });

    describe('DuplicateMap', () {
      DuplicateMap map;
      beforeEach(() => map = new DuplicateMap());

      it('should do basic operations', () {
        var k1 = 'a';
        var r1 = new ItemRecord(k1)..currentIndex = 1;
        map.put(r1);
        expect(map.get(k1, 2)).toEqual(null);
        expect(map.get(k1, 1)).toEqual(null);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.remove(r1)).toEqual(r1);
        expect(map.get(k1, -1)).toEqual(null);
      });

      it('should do basic operations on duplicate keys', () {
        var k1 = 'a';
        var r1 = new ItemRecord(k1)..currentIndex = 1;
        var r2 = new ItemRecord(k1)..currentIndex = 2;
        map..put(r1)..put(r2);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.get(k1, 1)).toEqual(r2);
        expect(map.get(k1, 2)).toEqual(null);
        expect(map.remove(r2)).toEqual(r2);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.remove(r1)).toEqual(r1);
        expect(map.get(k1, 0)).toEqual(null);
      });
    });
  });
}

class _User {
  String first;
  String last;
  num age;

  _User([this.first, this.last, this.age]);
}

Matcher toEqualCollectionRecord({collection, additions, moves, removals}) =>
    new CollectionRecordMatcher(collection:collection, additions:additions,
                                moves:moves, removals:removals);
Matcher toEqualMapRecord({map, additions, changes, removals}) =>
    new MapRecordMatcher(map:map, additions:additions,
                         changes:changes, removals:removals);
Matcher toEqualChanges(List changes) => new ChangeMatcher(changes);

class ChangeMatcher extends Matcher {
  List expected;

  ChangeMatcher(this.expected);

  Description describe(Description description) =>
      description..add(expected.toString());

  Description describeMismatch(Iterator<Record> changes,
                               Description mismatchDescription,
                               Map matchState, bool verbose) {
    List list = [];
    while(changes.moveNext()) {
      list.add(changes.current.handler);
    }
    return mismatchDescription..add(list.toString());
  }

  bool matches(Iterator<Record> changes, Map matchState) {
    int count = 0;
    while(changes.moveNext()) {
      if (changes.current.handler != expected[count++]) return false;
    }
    return count == expected.length;
  }
}

class CollectionRecordMatcher extends Matcher {
  final List collection;
  final List additions;
  final List moves;
  final List removals;

  CollectionRecordMatcher({this.collection, this.additions, this.moves,
                          this.removals});

  Description describeMismatch(changes, Description mismatchDescription,
                               Map matchState, bool verbose) {
    List diffs = matchState['diffs'];
    if (diffs == null) return mismatchDescription;
    return mismatchDescription..add(diffs.join('\n'));
  }

  Description describe(Description description) {
    add(name, collection) {
      if (collection != null) {
        description.add('$name: ${collection.join(', ')}\n   ');
      }
    }

    add('collection', collection);
    add('additions', additions);
    add('moves', moves);
    add('removals', removals);
    return description;
  }

  bool matches(CollectionChangeRecord changeRecord, Map matchState) {
    var diffs = matchState['diffs'] = [];
    return checkCollection(changeRecord, diffs) &&
           checkAdditions(changeRecord, diffs) &&
           checkMoves(changeRecord, diffs) &&
           checkRemovals(changeRecord, diffs);
  }

  bool checkCollection(CollectionChangeRecord changeRecord, List diffs) {
    var equals = true;
    int count = 0;
    if (collection != null) {
      CollectionItem collectionItem = changeRecord.collectionHead;
      for (var item in collection) {
        count++;
        if (collectionItem == null) {
          equals = false;
          diffs.add('collection too short: $item');
        } else {
          if (collectionItem.toString() != item) {
            equals = false;
            diffs.add('collection mismatch: $collectionItem != $item');
          }
          collectionItem = collectionItem.nextCollectionItem;
        }
      }
      if (collectionItem != null) {
        diffs.add('collection too long: $collectionItem');
        equals = false;
      }
    }
    var iterableLength = changeRecord.iterable.toList().length;
    if (iterableLength != count) {
      diffs.add('collection length mismatched: $iterableLength != $count');
      equals = false;
    }
    return equals;
  }

  bool checkAdditions(CollectionChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (additions != null) {
      AddedItem addedItem = changeRecord.additionsHead;
      for (var item in additions) {
        if (addedItem == null) {
          equals = false;
          diffs.add('additions too short: $item');
        } else {
          if (addedItem.toString() != item) {
            equals = false;
            diffs.add('additions mismatch: $addedItem != $item');
          }
          addedItem = addedItem.nextAddedItem;
        }
      }
      if (addedItem != null) {
        equals = false;
        diffs.add('additions too long: $addedItem');
      }
    }
    return equals;
  }

  bool checkMoves(CollectionChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (moves != null) {
      MovedItem movedItem = changeRecord.movesHead;
      for (var item in moves) {
        if (movedItem == null) {
          equals = false;
          diffs.add('moves too short: $item');
        } else {
          if (movedItem.toString() != item) {
            equals = false;
            diffs.add('moves too mismatch: $movedItem != $item');
          }
          movedItem = movedItem.nextMovedItem;
        }
      }
      if (movedItem != null) {
        equals = false;
        diffs.add('moves too long: $movedItem');
      }
    }
    return equals;
  }

  bool checkRemovals(CollectionChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (removals != null) {
      RemovedItem removedItem = changeRecord.removalsHead;
      for (var item in removals) {
        if (removedItem == null) {
          equals = false;
          diffs.add('removes too short: $item');
        } else {
          if (removedItem.toString() != item) {
            equals = false;
            diffs.add('removes too mismatch: $removedItem != $item');
          }
          removedItem = removedItem.nextRemovedItem;
        }
      }
      if (removedItem != null) {
        equals = false;
        diffs.add('removes too long: $removedItem');
      }
    }
    return equals;
  }
}

class MapRecordMatcher extends Matcher {
  final List map;
  final List additions;
  final List changes;
  final List removals;

  MapRecordMatcher({this.map, this.additions, this.changes, this.removals});

  Description describeMismatch(changes, Description mismatchDescription,
                               Map matchState, bool verbose) {
    List diffs = matchState['diffs'];
    if (diffs == null) return mismatchDescription;
    return mismatchDescription..add(diffs.join('\n'));
  }

  Description describe(Description description) {
    add(name, map) {
      if (map != null) {
        description.add('$name: ${map.join(', ')}\n   ');
      }
    }

    add('map', map);
    add('additions', additions);
    add('changes', changes);
    add('removals', removals);
    return description;
  }

  bool matches(MapChangeRecord changeRecord, Map matchState) {
    var diffs = matchState['diffs'] = [];
    return checkMap(changeRecord, diffs) &&
           checkAdditions(changeRecord, diffs) &&
           checkChanges(changeRecord, diffs) &&
           checkRemovals(changeRecord, diffs);
  }

  bool checkMap(MapChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (map != null) {
      KeyValue mapKeyValue = changeRecord.mapHead;
      for (var item in map) {
        if (mapKeyValue == null) {
          equals = false;
          diffs.add('map too short: $item');
        } else {
          if (mapKeyValue.toString() != item) {
            equals = false;
            diffs.add('map mismatch: $mapKeyValue != $item');
          }
          mapKeyValue = mapKeyValue.nextKeyValue;
        }
      }
      if (mapKeyValue != null) {
        diffs.add('map too long: $mapKeyValue');
        equals = false;
      }
    }
    return equals;
  }

  bool checkAdditions(MapChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (additions != null) {
      AddedKeyValue addedKeyValue = changeRecord.additionsHead;
      for (var item in additions) {
        if (addedKeyValue == null) {
          equals = false;
          diffs.add('additions too short: $item');
        } else {
          if (addedKeyValue.toString() != item) {
            equals = false;
            diffs.add('additions mismatch: $addedKeyValue != $item');
          }
          addedKeyValue = addedKeyValue.nextAddedKeyValue;
        }
      }
      if (addedKeyValue != null) {
        equals = false;
        diffs.add('additions too long: $addedKeyValue');
      }
    }
    return equals;
  }

  bool checkChanges(MapChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (changes != null) {
      ChangedKeyValue movedKeyValue = changeRecord.changesHead;
      for (var item in changes) {
        if (movedKeyValue == null) {
          equals = false;
          diffs.add('changes too short: $item');
        } else {
          if (movedKeyValue.toString() != item) {
            equals = false;
            diffs.add('changes too mismatch: $movedKeyValue != $item');
          }
          movedKeyValue = movedKeyValue.nextChangedKeyValue;
        }
      }
      if (movedKeyValue != null) {
        equals = false;
        diffs.add('changes too long: $movedKeyValue');
      }
    }
    return equals;
  }

  bool checkRemovals(MapChangeRecord changeRecord, List diffs) {
    var equals = true;
    if (removals != null) {
      RemovedKeyValue removedKeyValue = changeRecord.removalsHead;
      for (var item in removals) {
        if (removedKeyValue == null) {
          equals = false;
          diffs.add('rechanges too short: $item');
        } else {
          if (removedKeyValue.toString() != item) {
            equals = false;
            diffs.add('rechanges too mismatch: $removedKeyValue != $item');
          }
          removedKeyValue = removedKeyValue.nextRemovedKeyValue;
        }
      }
      if (removedKeyValue != null) {
        equals = false;
        diffs.add('rechanges too long: $removedKeyValue');
      }
    }
    return equals;
  }
}


class FooBar {
  static int fooIds = 0;

  int id;
  String foo, bar;

  FooBar(this.foo, this.bar) {
    id = fooIds++;
  }

  bool operator==(other) =>
      other is FooBar && foo == other.foo && bar == other.bar;

  int get hashCode =>
      foo.hashCode ^ bar.hashCode;

  toString() => '($id)$foo-$bar';
}
