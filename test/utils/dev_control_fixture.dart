// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A small app with one of each thing dev control drives: a button, a
/// long-press and right-click pad, a hover box, a text field, a shortcut,
/// a long list and an animation. [events] records what reached it.
class DevControlFixture extends StatefulWidget {
  final List<String> events;
  const DevControlFixture({required this.events, super.key});

  @override
  State<DevControlFixture> createState() => DevControlFixtureState();
}

class DevControlFixtureState extends State<DevControlFixture>
    with SingleTickerProviderStateMixin {
  int count = 0;
  bool hovered = false;
  final TextEditingController field = TextEditingController();
  late final AnimationController spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  final ScrollController list = ScrollController();

  void _log(String event) => setState(() => widget.events.add(event));

  @override
  void dispose() {
    field.dispose();
    spin.dispose();
    list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _log('ctrl+k'),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('counter'),
                    onPressed: () {
                      count++;
                      _log('tap');
                    },
                    child: const Text('Add one'),
                  ),
                  Text('Count: $count'),
                  GestureDetector(
                    key: const ValueKey('pad'),
                    onLongPress: () => _log('longpress'),
                    onSecondaryTap: () => _log('rightclick'),
                    child: Container(
                      width: 80,
                      height: 40,
                      color: Colors.amber,
                    ),
                  ),
                  MouseRegion(
                    key: const ValueKey('hoverbox'),
                    onEnter: (_) => setState(() => hovered = true),
                    onExit: (_) => setState(() => hovered = false),
                    child: Container(
                      width: 80,
                      height: 40,
                      color: hovered ? Colors.green : Colors.grey,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings),
                    onPressed: () => _log('settings'),
                  ),
                  FilledButton(
                    key: const ValueKey('spin'),
                    onPressed: () => spin.repeat(),
                    child: const Text('Spin'),
                  ),
                  RotationTransition(
                    turns: spin,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  key: const ValueKey('field'),
                  controller: field,
                  onChanged: (v) => _log('changed:$v'),
                  onSubmitted: (v) => _log('submitted:$v'),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey('list'),
                  controller: list,
                  itemCount: 200,
                  itemExtent: 50,
                  itemBuilder: (context, i) => ListTile(title: Text('Item $i')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
