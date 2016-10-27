#!/bin/bash
set -e # bail on error

cd $( dirname "${BASH_SOURCE[0]}" )/..

./tool/build_sdk.sh

mkdir -p gen/codegen_output/pkg/

SDK=--dart-sdk-summary=lib/js/amd/dart_sdk.sum

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/expect.js \
    package:expect/expect.dart \
    package:expect/minitest.dart

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/async_helper.js \
    --url-mapping=package:async_helper/async_helper.dart,test/codegen/async_helper.dart \
    package:async_helper/async_helper.dart

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/js.js \
    package:js/js.dart

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/matcher.js \
    package:matcher/matcher.dart

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/path.js \
    package:path/path.dart

./bin/dartdevc.dart $SDK -o gen/codegen_output/pkg/stack_trace.js \
    -s gen/codegen_output/pkg/path.sum \
    package:stack_trace/stack_trace.dart
