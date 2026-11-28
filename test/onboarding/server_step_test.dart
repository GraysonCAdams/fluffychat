// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_state.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('server step lookup', () {
    late List<Uri> asked;
    late Map<String, FutureOr<SignInMethod> Function()> answers;

    SignInViewModel make() => SignInViewModel(
      null,
      signUp: false,
      checkServer: (uri) async {
        asked.add(uri);
        return answers[uri.host]!();
      },
    );

    setUp(() {
      asked = [];
      answers = {};
    });

    test('waits for typing to pause, then finds the server', () {
      fakeAsync((async) {
        answers['d.graysons.network'] = () => SignInMethod.oidc;
        final vm = make();
        vm.serverController.text = '@gray:d.graysons';
        async.elapse(const Duration(milliseconds: 200));
        vm.serverController.text = '@gray:d.graysons.network';
        expect(asked, isEmpty, reason: 'no lookup while typing');
        async.elapse(SignInViewModel.lookupDelay);
        expect(asked, [Uri.https('d.graysons.network', '')]);
        async.flushMicrotasks();
        final lookup = vm.value.lookup;
        expect(lookup.status, ServerLookupStatus.found);
        expect(lookup.method, SignInMethod.oidc);
        expect(lookup.input!.username, 'gray');
        vm.dispose();
      });
    });

    test('a server that does not answer is unreachable', () {
      fakeAsync((async) {
        answers['nowhere.example'] = () =>
            throw http.ClientException('Failed host lookup');
        final vm = make();
        vm.serverController.text = 'nowhere.example';
        async.elapse(SignInViewModel.lookupDelay);
        async.flushMicrotasks();
        expect(vm.value.lookup.status, ServerLookupStatus.unreachable);
        vm.dispose();
      });
    });

    test('an address that answers but is not Matrix', () {
      fakeAsync((async) {
        answers['example.com'] = () => throw const FormatException('<html>');
        final vm = make();
        vm.serverController.text = 'example.com';
        async.elapse(SignInViewModel.lookupDelay);
        async.flushMicrotasks();
        expect(vm.value.lookup.status, ServerLookupStatus.notMatrix);
        vm.dispose();
      });
    });

    test('an answer for text since replaced is dropped', () {
      fakeAsync((async) {
        final slow = Completer<SignInMethod>();
        answers['slow.example'] = () => slow.future;
        answers['fast.example'] = () => SignInMethod.password;
        final vm = make();
        vm.serverController.text = 'slow.example';
        async.elapse(SignInViewModel.lookupDelay);
        vm.serverController.text = 'fast.example';
        async.elapse(SignInViewModel.lookupDelay);
        async.flushMicrotasks();
        slow.complete(SignInMethod.oidc);
        async.flushMicrotasks();
        expect(vm.value.lookup.input!.label, 'fast.example');
        expect(vm.value.lookup.method, SignInMethod.password);
        vm.dispose();
      });
    });

    test('text that cannot be a server clears the lookup', () {
      fakeAsync((async) {
        final vm = make();
        vm.serverController.text = 'd.';
        async.elapse(SignInViewModel.lookupDelay);
        expect(asked, isEmpty);
        expect(vm.value.lookup.status, ServerLookupStatus.idle);
        vm.dispose();
      });
    });
  });

  test('SignInMethod prefers OIDC, then SSO, then password', () {
    expect(SignInMethod.of([], null, preferOidc: true), SignInMethod.password);
  });
}
