// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// Settings > Chats > Matrix features: whether Matrix-only features follow
/// auto detection or are always shown or hidden, what auto detection
/// decided, and a row per feature whose tap overrides it.
class SettingsMatrixFeatures extends StatelessWidget {
  const SettingsMatrixFeatures({super.key});

  static String featureTitle(L10n l10n, MatrixFeature feature) =>
      switch (feature) {
        MatrixFeature.status => l10n.matrixFeatureStatus,
        MatrixFeature.identity => l10n.matrixFeatureIdentity,
        MatrixFeature.fullUserIds => l10n.matrixFeatureFullUserIds,
        MatrixFeature.spaces => l10n.matrixFeatureSpaces,
        MatrixFeature.explore => l10n.matrixFeatureExplore,
        MatrixFeature.roomPlumbing => l10n.matrixFeatureRoomPlumbing,
        MatrixFeature.customEmotes => l10n.matrixFeatureCustomEmotes,
      };

  /// What makes [feature] show in auto mode.
  static String _trigger(L10n l10n, MatrixFeature feature, bool shown) =>
      switch (feature) {
        MatrixFeature.fullUserIds when !shown =>
          l10n.matrixFeatureTriggerFullUserIds,
        MatrixFeature.status ||
        MatrixFeature.identity ||
        MatrixFeature.fullUserIds ||
        MatrixFeature.explore => l10n.matrixFeatureTriggerFirstContact,
        MatrixFeature.spaces => l10n.matrixFeatureTriggerSpaces,
        MatrixFeature.roomPlumbing => l10n.matrixFeatureTriggerRoomPlumbing,
        MatrixFeature.customEmotes => l10n.matrixFeatureTriggerCustomEmotes,
      };

  /// The state of [feature] and why, such as "Hidden · shows after your
  /// first Matrix contact".
  static String stateLine(
    L10n l10n,
    MatrixFeatures features,
    MatrixFeature feature,
  ) {
    final override = features.overrides[feature];
    final mode = features.mode;
    final perChat =
        override == null &&
        mode == MatrixFeaturesMode.auto &&
        feature == MatrixFeature.roomPlumbing;
    final shown = features.isRelevant(feature);
    final state = perChat
        ? l10n.matrixFeaturePerChat
        : shown
        ? l10n.matrixFeatureShown
        : l10n.matrixFeatureHidden;
    final reason = override != null
        ? l10n.matrixFeatureYourChoice
        : switch (mode) {
            MatrixFeaturesMode.alwaysShow => l10n.matrixFeaturesAlwaysShow,
            MatrixFeaturesMode.alwaysHide => l10n.matrixFeaturesAlwaysHide,
            MatrixFeaturesMode.auto => _trigger(l10n, feature, shown),
          };
    return l10n.matrixFeatureState(state, reason);
  }

  Future<void> _pickOverride(
    BuildContext context,
    MatrixFeatures features,
    MatrixFeature feature,
  ) async {
    final l10n = L10n.of(context);
    final current = features.overrides[feature];
    final picked = await showDialog<(MatrixFeatureOverride?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(featureTitle(l10n, feature)),
        children: [
          for (final (value, label) in [
            (null, l10n.matrixFeatureFollowMode),
            (MatrixFeatureOverride.show, l10n.matrixFeatureShow),
            (MatrixFeatureOverride.hide, l10n.matrixFeatureHide),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop((value,)),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await features.setOverride(feature, picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final features = MatrixFeatures.forClient(Matrix.of(context).client);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.matrixFeatures),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: MaxWidthBody(
        child: ListenableBuilder(
          listenable: features,
          builder: (context, _) {
            final signals = features.signals;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(subtitle: Text(l10n.matrixFeaturesDescription)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<MatrixFeaturesMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: MatrixFeaturesMode.auto,
                        label: Text(l10n.matrixFeaturesAuto),
                      ),
                      ButtonSegment(
                        value: MatrixFeaturesMode.alwaysShow,
                        label: Text(l10n.matrixFeaturesAlwaysShow),
                      ),
                      ButtonSegment(
                        value: MatrixFeaturesMode.alwaysHide,
                        label: Text(l10n.matrixFeaturesAlwaysHide),
                      ),
                    ],
                    selected: {features.mode},
                    onSelectionChanged: (selected) =>
                        features.setMode(selected.single),
                  ),
                ),
                ListTile(
                  subtitle: Text(
                    signals.messengerMode
                        ? l10n.matrixFeaturesAutoMessengerMode(
                            signals.realContacts,
                          )
                        : l10n.matrixFeaturesAutoAllFeatures(
                            signals.realContacts,
                          ),
                  ),
                ),
                for (final feature in MatrixFeature.values)
                  ListTile(
                    key: ValueKey('matrix_feature_${feature.name}'),
                    title: Text(featureTitle(l10n, feature)),
                    subtitle: Text(
                      stateLine(l10n, features, feature),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => _pickOverride(context, features, feature),
                  ),
                ListTile(subtitle: Text(l10n.matrixFeaturesFooter)),
              ],
            );
          },
        ),
      ),
    );
  }
}
