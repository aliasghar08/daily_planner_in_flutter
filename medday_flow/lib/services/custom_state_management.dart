import 'package:flutter/widgets.dart';

/// Base interface for widgets that can be nested in [MultiProvider].
abstract class SingleChildWidget extends Widget {
  const SingleChildWidget({super.key});
  Widget buildWithChild(BuildContext context, Widget? child);
}

/// A lightweight, pure Flutter [InheritedNotifier] provider that manages a [ChangeNotifier].
/// Completely eliminates the need for external `package:provider`.
class ChangeNotifierProvider<T extends ChangeNotifier> extends StatefulWidget
    implements SingleChildWidget {
  final T Function(BuildContext context)? create;
  final T? value;
  final Widget? child;
  final Widget Function(BuildContext context, Widget? child)? builder;
  final bool lazy;

  const ChangeNotifierProvider({
    super.key,
    required T Function(BuildContext context) this.create,
    this.child,
    this.builder,
    this.lazy = true,
  }) : value = null;

  const ChangeNotifierProvider.value({
    super.key,
    required T this.value,
    this.child,
    this.builder,
  })  : create = null,
        lazy = false;

  @override
  State<ChangeNotifierProvider<T>> createState() =>
      _ChangeNotifierProviderState<T>();

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    if (create != null) {
      return ChangeNotifierProvider<T>(
        key: key,
        create: create!,
        builder: builder,
        child: child,
      );
    } else {
      return ChangeNotifierProvider<T>.value(
        key: key,
        value: value as T,
        builder: builder,
        child: child,
      );
    }
  }
}

class _ChangeNotifierProviderState<T extends ChangeNotifier>
    extends State<ChangeNotifierProvider<T>> {
  T? _notifier;
  bool _createdInternally = false;

  @override
  void initState() {
    super.initState();
    if (widget.create != null) {
      _notifier = widget.create!(context);
      _createdInternally = true;
    } else {
      _notifier = widget.value;
      _createdInternally = false;
    }
  }

  @override
  void didUpdateWidget(covariant ChangeNotifierProvider<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != _notifier) {
      if (_createdInternally) {
        _notifier?.dispose();
      }
      _notifier = widget.value;
      _createdInternally = false;
    }
  }

  @override
  void dispose() {
    if (_createdInternally) {
      _notifier?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveNotifier = _notifier ?? widget.value;
    final Widget current = _InheritedChangeNotifier<T>(
      notifier: effectiveNotifier,
      child: widget.builder != null
          ? Builder(
              builder: (ctx) => widget.builder!(ctx, widget.child),
            )
          : (widget.child ?? const SizedBox.shrink()),
    );
    return current;
  }
}

/// Internal [InheritedNotifier] to propagate changes down the widget tree.
class _InheritedChangeNotifier<T extends ChangeNotifier>
    extends InheritedNotifier<T> {
  const _InheritedChangeNotifier({
    super.key,
    required super.notifier,
    required super.child,
  });
}

/// MultiProvider combines multiple [SingleChildWidget] providers into a single linear widget tree.
class MultiProvider extends StatelessWidget {
  final List<dynamic> providers;
  final Widget? child;
  final Widget Function(BuildContext context, Widget? child)? builder;

  const MultiProvider({
    super.key,
    required this.providers,
    this.child,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    Widget tree = widgetChild(context);
    for (final provider in providers.reversed) {
      if (provider is SingleChildWidget) {
        tree = provider.buildWithChild(context, tree);
      } else if (provider is Widget) {
        tree = provider;
      }
    }
    return tree;
  }

  Widget widgetChild(BuildContext context) {
    if (builder != null) {
      return Builder(builder: (ctx) => builder!(ctx, child));
    }
    return child ?? const SizedBox.shrink();
  }
}

/// Static helper matching the `Provider` API.
class Provider {
  /// Obtains the [T] from the closest ancestor [ChangeNotifierProvider].
  static T of<T extends ChangeNotifier>(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final inherited = context
          .dependOnInheritedWidgetOfExactType<_InheritedChangeNotifier<T>>();
      if (inherited == null || inherited.notifier == null) {
        throw FlutterError(
          'Could not find ChangeNotifierProvider<$T> in widget tree.\n'
          'Ensure the widget is wrapped in a ChangeNotifierProvider<$T>.',
        );
      }
      return inherited.notifier!;
    } else {
      final inherited = context
          .getElementForInheritedWidgetOfExactType<
              _InheritedChangeNotifier<T>>()
          ?.widget as _InheritedChangeNotifier<T>?;
      if (inherited == null || inherited.notifier == null) {
        throw FlutterError(
          'Could not find ChangeNotifierProvider<$T> in widget tree.\n'
          'Ensure the widget is wrapped in a ChangeNotifierProvider<$T>.',
        );
      }
      return inherited.notifier!;
    }
  }
}

/// Consumer widget rebuilding only its subtree when [T] notifies listeners.
class Consumer<T extends ChangeNotifier> extends StatelessWidget {
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const Consumer({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final value = Provider.of<T>(context, listen: true);
    return builder(context, value, child);
  }
}

/// Consumer2 widget rebuilding when either [A] or [B] notifies listeners.
class Consumer2<A extends ChangeNotifier, B extends ChangeNotifier>
    extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    A valueA,
    B valueB,
    Widget? child,
  ) builder;
  final Widget? child;

  const Consumer2({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final valueA = Provider.of<A>(context, listen: true);
    final valueB = Provider.of<B>(context, listen: true);
    return builder(context, valueA, valueB, child);
  }
}

/// Extension on [BuildContext] for ergonomic provider access.
extension CustomProviderContextExtensions on BuildContext {
  /// Read [T] without subscribing to widget rebuilds.
  T read<T extends ChangeNotifier>() => Provider.of<T>(this, listen: false);

  /// Watch [T] and trigger widget rebuilds when notifications occur.
  T watch<T extends ChangeNotifier>() => Provider.of<T>(this, listen: true);
}
