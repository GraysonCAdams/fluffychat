// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:fluffychat/utils/voice_transcription/voice_transcriber.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// "Show transcript" toggle for an audio message, transcribed on the device.
class AudioTranscript extends StatefulWidget {
  final Event event;
  final Color color;
  final double fontSize;

  const AudioTranscript(
    this.event, {
    required this.color,
    required this.fontSize,
    super.key,
  });

  @override
  State<AudioTranscript> createState() => _AudioTranscriptState();
}

class _AudioTranscriptState extends State<AudioTranscript> {
  String? _transcript;
  bool _visible = false;
  bool _transcribing = false;
  double? _downloadProgress;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle() async {
    if (_visible) {
      setState(() => _visible = false);
      return;
    }
    final eventId = widget.event.eventId;
    final transcript = _transcript ?? await VoiceTranscriber.cache.get(eventId);
    if (transcript != null) {
      setState(() {
        _transcript = transcript;
        _visible = true;
      });
      return;
    }
    if (!await _ensureModel()) return;

    setState(() => _transcribing = true);
    try {
      final file = await widget.event.downloadAndDecryptAttachment();
      final text = await VoiceTranscriber.transcribe(file.bytes, file.name);
      await VoiceTranscriber.cache.put(eventId, text);
      if (!mounted) return;
      setState(() {
        _transcript = text;
        _visible = true;
      });
    } catch (e, s) {
      Logs().w('Could not transcribe audio message', e, s);
      if (!mounted) return;
      _showError(L10n.of(context).transcriptionFailed);
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<bool> _ensureModel() async {
    if (await VoiceTranscriber.isModelDownloaded()) return true;
    if (!mounted) return false;
    final l10n = L10n.of(context);
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.downloadTranscriptionModel,
      message: l10n.downloadTranscriptionModelDescription(
        VoiceTranscriber.modelSizeBytes.sizeString,
      ),
      okLabel: l10n.download,
      cancelLabel: l10n.cancel,
    );
    if (consent != OkCancelResult.ok) return false;

    setState(() => _downloadProgress = 0);
    try {
      await VoiceTranscriber.downloadModel(
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      return true;
    } catch (e, s) {
      Logs().w('Could not download transcription model', e, s);
      if (mounted) _showError(e.toLocalizedString(context));
      return false;
    } finally {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final downloadProgress = _downloadProgress;
    final busy = _transcribing || downloadProgress != null;
    final transcript = _transcript;
    final label = downloadProgress != null
        ? l10n.downloadingTranscriptionModel(
            (downloadProgress * 100).clamp(0, 100).round(),
          )
        : _transcribing
        ? l10n.transcribing
        : _visible
        ? l10n.hideTranscript
        : l10n.showTranscript;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: widget.color,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: busy ? null : _toggle,
          icon: busy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                    value: downloadProgress,
                  ),
                )
              : const Icon(Icons.subtitles_outlined, size: 16),
          label: Text(
            label,
            style: TextStyle(color: widget.color, fontSize: 12),
          ),
        ),
        if (_visible && transcript != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              transcript.isEmpty ? l10n.noSpeechDetected : transcript,
              style: TextStyle(
                color: widget.color,
                fontSize: widget.fontSize,
                fontStyle: transcript.isEmpty ? FontStyle.italic : null,
              ),
            ),
          ),
      ],
    );
  }
}
