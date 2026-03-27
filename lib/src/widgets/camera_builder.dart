import 'package:flutter/material.dart';

import '../controller/camera_controller.dart';
import '../models/camera_builder_state.dart';
import '../models/camera_config.dart';
import '../models/camera_description.dart';
import '../models/camera_exception.dart';
import '../models/camera_state.dart';
import 'camera_preview.dart';

typedef CameraLayoutBuilder =
    Widget Function(
      BuildContext context,
      CameraBuilderState state,
      Widget preview,
    );

class CameraBuilder extends StatefulWidget {
  const CameraBuilder({
    super.key,
    required this.builder,
    this.preferredLens = LensDirection.front,
    this.config = const CameraConfig(),
  });

  final CameraLayoutBuilder builder;
  final LensDirection preferredLens;
  final CameraConfig config;

  @override
  State<CameraBuilder> createState() => _CameraBuilderState();
}

class _CameraBuilderState extends State<CameraBuilder> {
  CameraController? _controller;
  CameraException? _setupError;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant CameraBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferredLens != oldWidget.preferredLens ||
        widget.config != oldWidget.config) {
      _createController();
    }
  }

  @override
  void dispose() {
    _controller?.disposeCamera();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _createController() async {
    final previousController = _controller;

    setState(() {
      _setupError = null;
      _controller = null;
    });

    try {
      final controller = await CameraController.create(
        preferredLens: widget.preferredLens,
        config: widget.config,
      );
      await controller.prewarmUp();
      if (!mounted) {
        await controller.disposeCamera();
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
      });

      await previousController?.disposeCamera();
      previousController?.dispose();
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _setupError = error;
      });
      await previousController?.disposeCamera();
      previousController?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      final state = _setupError == null
          ? CameraBuilderPreparingState(config: widget.config)
          : CameraBuilderErrorState(
              config: widget.config,
              error: _setupError!,
              retry: _createController,
            );
      return widget.builder(context, state, const _CameraPlaceholderPreview());
    }

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, CameraState value, _) {
        final state = CameraBuilderState.fromController(controller, value);
        return widget.builder(
          context,
          state,
          CameraPreview(controller: controller),
        );
      },
    );
  }
}

class _CameraPlaceholderPreview extends StatelessWidget {
  const _CameraPlaceholderPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black);
  }
}
