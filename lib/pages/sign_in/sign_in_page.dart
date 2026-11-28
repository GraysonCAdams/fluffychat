// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_state.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:fluffychat/utils/sign_in_flows/check_homeserver.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/view_model_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The server step: "Where is your account?". One field takes a server
/// address or a full Matrix ID; once typing pauses the server is looked up
/// and a card says how it signs in. Continue goes on to that sign-in.
class SignInPage extends StatelessWidget {
  final bool signUp;
  const SignInPage({required this.signUp, super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final signedInUserId = matrix.widget.clients
        .where((client) => client.isLogged())
        .firstOrNull
        ?.userID;
    return ViewModelBuilder(
      create: () => SignInViewModel(matrix, signUp: signUp),
      builder: (context, viewModel, _) => ServerStepView(
        viewModel: viewModel,
        signUp: signUp,
        signedInUserId: signedInUserId,
      ),
    );
  }
}

class ServerStepView extends StatelessWidget {
  final SignInViewModel viewModel;
  final bool signUp;

  /// The account already signed in, when this adds another one.
  final String? signedInUserId;

  const ServerStepView({
    required this.viewModel,
    required this.signUp,
    this.signedInUserId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final signedInUserId = this.signedInUserId;
    final state = viewModel.value;
    final lookup = state.lookup;
    final loading =
        state.loginLoading.connectionState == ConnectionState.waiting;
    final input = lookup.input;
    final found = lookup.status == ServerLookupStatus.found;
    // The server signed in to last; the default server until then,
    // except in the Play build, which recommends none.
    final remembered =
        AppSettings.store.getString(AppSettings.defaultHomeserver.key) ??
        (AppConfig.isPlayRelease ? null : AppSettings.defaultHomeserver.value);

    void submit() {
      if (!found || loading || input == null) return;
      final picked = state.pickedPublicHomeserver;
      connectToHomeserverFlow(
        picked ??
            PublicHomeserverData(
              name:
                  input.homeserver.scheme == 'https' &&
                      !input.homeserver.hasPort
                  ? input.label
                  : input.homeserver.toString(),
            ),
        context,
        viewModel.setLoginLoading,
        signUp,
        username: input.username,
      );
    }

    final String headline;
    final String body;
    if (signedInUserId != null) {
      headline = l10n.addAnotherAccount;
      body = l10n.addAccountBody(signedInUserId);
    } else if (signUp) {
      headline = l10n.serverStepSignUpTitle;
      body = l10n.serverStepSignUpBody;
    } else {
      headline = l10n.serverStepTitle;
      body = l10n.serverStepBody;
    }

    return OnboardingStep(
      leading: loading
          ? CloseButton(
              onPressed: () =>
                  viewModel.setLoginLoading(const AsyncSnapshot.nothing()),
            )
          : BackButton(onPressed: Navigator.of(context).pop),
      appBarTitle: signedInUserId != null ? l10n.addAccount : null,
      headline: headline,
      body: body,
      content: [
        TextField(
          controller: viewModel.serverController,
          readOnly: loading,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => submit(),
          autofillHints: const [AutofillHints.url],
          decoration: InputDecoration(
            labelText: l10n.serverOrMatrixId,
            hintText: l10n.serverFieldHint,
            prefixIcon: const Icon(Icons.dns_outlined),
            suffixIcon: switch (lookup.status) {
              ServerLookupStatus.checking => const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              ServerLookupStatus.found => Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              _ => null,
            },
            helperText: lookup.status == ServerLookupStatus.idle
                ? l10n.serverFieldHelper
                : null,
            helperMaxLines: 2,
            errorText: switch (lookup.status) {
              ServerLookupStatus.unreachable => l10n.serverUnreachable(
                input!.label,
              ),
              ServerLookupStatus.notMatrix => l10n.serverNotMatrix(
                input!.label,
              ),
              _ => null,
            },
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        if (lookup.status == ServerLookupStatus.checking && input != null)
          OnboardingNotice(
            icon: Icons.travel_explore,
            text: l10n.lookingForServer(input.label),
          )
        else if (found && input != null)
          _ServerCard(label: input.label, method: lookup.method!)
        else if (lookup.status == ServerLookupStatus.idle &&
            remembered != null &&
            remembered.isNotEmpty) ...[
          Text(
            l10n.recentServers,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.history, size: 18),
                label: Text(remembered),
                onPressed: () => viewModel.useServer(remembered),
              ),
            ],
          ),
        ],
      ],
      primary: loading
          ? const OnboardingBusyButton()
          : FilledButton(
              onPressed: found ? submit : null,
              child: Text(l10n.continueText),
            ),
      secondary: [
        if (lookup.status == ServerLookupStatus.unreachable ||
            lookup.status == ServerLookupStatus.notMatrix)
          OutlinedButton.icon(
            onPressed: viewModel.retryLookup,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.tryAgain),
          )
        else if (!AppConfig.isPlayRelease)
          TextButton(
            onPressed: loading
                ? null
                : () => _showPublicServers(context, viewModel),
            child: Text(l10n.browsePublicServers),
          ),
        if (signedInUserId != null)
          TextButton(
            onPressed: loading
                ? null
                : () => context.go(
                    signUp
                        ? '/rooms/settings/addaccount/sign_in'
                        : '/rooms/settings/addaccount/sign_up',
                  ),
            child: Text(
              signUp ? l10n.signInInstead : l10n.createAccountInstead,
            ),
          ),
      ],
    );
  }

  Future<void> _showPublicServers(
    BuildContext context,
    SignInViewModel viewModel,
  ) async {
    viewModel.loadPublicHomeservers();
    final picked = await showModalBottomSheet<PublicHomeserverData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PublicServersSheet(viewModel: viewModel),
    );
    if (picked?.name == null) return;
    viewModel.useServer(picked!.name!, publicData: picked);
  }
}

class _ServerCard extends StatelessWidget {
  final String label;
  final SignInMethod method;

  const _ServerCard({required this.label, required this.method});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(
                method.usesBrowser
                    ? Icons.open_in_browser
                    : Icons.password_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.usesBrowser
                        ? l10n.serverSignsInOnItsPage
                        : l10n.serverSignsInWithPassword,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicServersSheet extends StatefulWidget {
  final SignInViewModel viewModel;
  const _PublicServersSheet({required this.viewModel});

  @override
  State<_PublicServersSheet> createState() => _PublicServersSheetState();
}

class _PublicServersSheetState extends State<_PublicServersSheet> {
  PublicHomeserverData? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: widget.viewModel,
      builder: (context, state, _) {
        final servers = state.publicHomeservers;
        final selected = _selected ?? servers.data?.firstOrNull;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  l10n.publicServersDescription,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              if (servers.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (servers.hasError)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.oopsSomethingWentWrong),
                )
              else
                Flexible(
                  child: RadioGroup<PublicHomeserverData>(
                    groupValue: selected,
                    onChanged: (server) => setState(() => _selected = server),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final server in servers.data!)
                          RadioListTile(
                            value: server,
                            title: Row(
                              children: [
                                Expanded(child: Text(server.name ?? 'Unknown')),
                                if (server.website != null)
                                  IconButton(
                                    tooltip: server.website,
                                    icon: const Icon(
                                      Icons.open_in_new_outlined,
                                      size: 16,
                                    ),
                                    onPressed: () =>
                                        launchUrlString(server.website!),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              [
                                server.description,
                                ...?server.languages,
                              ].whereType<String>().join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: OnboardingButtonTheme(
                  child: FilledButton(
                    onPressed: selected == null
                        ? null
                        : () => Navigator.of(context).pop(selected),
                    child: Text(l10n.useServer(selected?.name ?? '')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
