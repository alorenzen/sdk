// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/index2/index2.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/summary/idl.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:unittest/unittest.dart';

import '../../abstract_single_unit.dart';
import '../../utils.dart';

main() {
  initializeTestEnvironment();
  defineReflectiveTests(Index2Test);
}

@reflectiveTest
class Index2Test extends AbstractSingleUnitTest {
  Index2 index = createMemoryIndex2();

  /**
   * Return the [Location] with given properties, or fail.
   */
  Location findLocation(List<Location> locations, String libraryUri,
      String unitUri, int offset, int length) {
    for (Location location in locations) {
      if (location.libraryUri == libraryUri &&
          location.unitUri == unitUri &&
          location.offset == offset &&
          location.length == length) {
        return location;
      }
    }
    fail('No at $offset with length $length in\n${locations.join('\n')}');
    return null;
  }

  /**
   * Return the [Location] with given properties, or fail.
   */
  Location findLocationSource(
      List<Location> locations, Source source, String search,
      {int length}) {
    String code = source.contents.data;
    int offset = code.indexOf(search);
    expect(offset, isNonNegative, reason: 'Not found "$search" in\n$code');
    length ??= getLeadingIdentifierLength(search);
    String uri = source.uri.toString();
    return findLocation(locations, uri, uri, offset, length);
  }

  /**
   * Return the [Location] with given properties, or fail.
   */
  Location findLocationTest(List<Location> locations, String search,
      {int length}) {
    int offset = findOffset(search);
    length ??= getLeadingIdentifierLength(search);
    String testUri = testSource.uri.toString();
    return findLocation(locations, testUri, testUri, offset, length);
  }

  void setUp() {
    super.setUp();
  }

  void tearDown() {
    super.tearDown();
    index = null;
  }

  test_getDefinedNames_classMember() async {
    _indexTestUnit('''
class A {
  test() {}
}
class B {
  int test = 1;
  main() {
    int test = 2;
  }
}
''');
    ClassElement classA = findElement('A');
    ClassElement classB = findElement('B');
    List<Location> locations = await index.getDefinedNames(
        new RegExp(r'^test$'), IndexNameKind.classMember);
    expect(locations, hasLength(2));
    _assertHasDefinedName(locations, classA.methods[0]);
    _assertHasDefinedName(locations, classB.fields[0]);
  }

  test_getDefinedNames_topLevel() async {
    _indexTestUnit('''
class A {} // A
class B = Object with A;
typedef C();
D() {}
var E = null;
class NoMatchABCDE {}
''');
    Element topA = findElement('A');
    Element topB = findElement('B');
    Element topC = findElement('C');
    Element topD = findElement('D');
    Element topE = findElement('E');
    List<Location> locations = await index.getDefinedNames(
        new RegExp(r'^[A-E]$'), IndexNameKind.topLevel);
    expect(locations, hasLength(5));
    _assertHasDefinedName(locations, topA);
    _assertHasDefinedName(locations, topB);
    _assertHasDefinedName(locations, topC);
    _assertHasDefinedName(locations, topD);
    _assertHasDefinedName(locations, topE);
  }

  test_getRelations_isExtendedBy() async {
    _indexTestUnit(r'''
class A {}
class B extends A {} // B
''');
    Source source2 = _indexUnit(
        '/test2.dart',
        r'''
import 'test.dart';
class C extends A {} // C
''');
    ClassElement elementA = testUnitElement.getType('A');
    List<Location> locations =
        await index.getRelations(elementA, IndexRelationKind.IS_EXTENDED_BY);
    findLocationTest(locations, 'A {} // B');
    findLocationSource(locations, source2, 'A {} // C');
  }

  test_getRelations_isReferencedBy() async {
    _indexTestUnit(r'''
main(int a, int b) {
}
''');
    ClassElement intElement = context.typeProvider.intType.element;
    List<Location> locations = await index.getRelations(
        intElement, IndexRelationKind.IS_REFERENCED_BY);
    findLocationTest(locations, 'int a');
    findLocationTest(locations, 'int b');
  }

  test_getUnresolvedMemberReferences() async {
    _indexTestUnit('''
class A {
  var test; // A
  mainA() {
    test(); // a-inv-r-nq
    test = 1; // a-ref-r-nq
    test += 2; // a-ref-r-nq
    print(test); // a-ref-r-nq
  }
}
main(A a, p) {
  a.test(); // a-inv-r-q
  a.test = 1; // a-ref-r-q
  a.test += 2; // a-ref-r-q
  print(a.test); // a-ref-r-q
  p.test(); // p-inv-ur-q
  p.test = 1; // p-ref-ur-q
  p.test += 2; // p-ref-ur-q
  print(p.test); // p-ref-ur-q
}
''');
    List<Location> locations =
        await index.getUnresolvedMemberReferences('test');
    expect(locations, hasLength(4));
    findLocationTest(locations, 'test(); // p-inv-ur-q');
    findLocationTest(locations, 'test = 1; // p-ref-ur-q');
    findLocationTest(locations, 'test += 2; // p-ref-ur-q');
    findLocationTest(locations, 'test); // p-ref-ur-q');
  }

  /**
   * Assert that the given list of [locations] has a [Location] corresponding
   * to the [element].
   */
  void _assertHasDefinedName(List<Location> locations, Element element) {
    String libraryUri = element.library.source.uri.toString();
    String unitUri = element.source.uri.toString();
    for (Location location in locations) {
      if (location.libraryUri == libraryUri &&
          location.unitUri == unitUri &&
          location.offset == element.nameOffset &&
          location.length == element.nameLength) {
        return;
      }
    }
    fail('No declaration of $element at ${element.nameOffset} in\n'
        '${locations.join('\n')}');
  }

  void _indexTestUnit(String code) {
    resolveTestUnit(code);
    index.indexUnit(testUnit);
  }

  Source _indexUnit(String path, String code) {
    Source source = addSource(path, code);
    CompilationUnit unit = resolveLibraryUnit(source);
    index.indexUnit(unit);
    return source;
  }
}