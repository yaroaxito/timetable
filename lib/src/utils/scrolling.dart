// Taken from (modified): https://github.com/google/flutter.widgets/blob/55cdc9a8315246732aca30fc02317f658b2e8a23/packages/linked_scroll_controller/lib/linked_scroll_controller.dart

// Copyright 2018 the Dart project authors.
//
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file or at
// https://developers.google.com/open-source/licenses/bsd

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Sets up a collection of scroll controllers that mirror their movements to
/// each other.
///
/// Controllers are added and returned via [addAndGet]. The initial offset
/// of the newly created controller is synced to the current offset.
/// Controllers must be `dispose`d when no longer in use to prevent memory
/// leaks and performance degradation.
///
/// If controllers are disposed over the course of the lifetime of this
/// object the corresponding scrollables should be given unique keys.
/// Without the keys, Flutter may reuse a controller after it has been disposed,
/// which can cause the controller offsets to fall out of sync.
class LinkedScrollControllerGroup {
  LinkedScrollControllerGroup({
    double initialPage = 0,
    this.viewportFraction = 1,
  })  : assert(initialPage != null),
        assert(viewportFraction != null) {
    _pageNotifier = ValueNotifier(initialPage);
  }

  final double viewportFraction;

  final _allControllers = <_LinkedScrollController>[];

  ValueNotifier<double> _pageNotifier;

  /// The current page of the group.
  double get page => _pageNotifier.value;
  ValueListenable<double> get pageListenable => _pageNotifier;

  /// Creates a new controller that is linked to any existing ones.
  ScrollController addAndGet() {
    final controller = _LinkedScrollController(this);
    _allControllers.add(controller);
    controller.addListener(() {
      _pageNotifier.value = controller.page;
    });
    return controller;
  }

  /// Adds a callback that will be called when the value of [page] changes.
  void addPageChangedListener(VoidCallback onChanged) {
    _pageNotifier.addListener(onChanged);
  }

  /// Removes the specified page changed listener.
  void removePageChangedListener(VoidCallback listener) {
    _pageNotifier.removeListener(listener);
  }

  Iterable<_LinkedScrollController> get _attachedControllers =>
      _allControllers.where((controller) => controller.hasClients);

  /// Animates the scroll position of all linked controllers to [page].
  Future<void> animateTo(
    double page, {
    @required Curve curve,
    @required Duration duration,
  }) async {
    final animations = <Future<void>>[];
    for (final controller in _attachedControllers) {
      animations.add(controller.animateToPage(
        page,
        duration: duration,
        curve: curve,
      ));
    }
    return Future.wait<void>(animations).then<void>((_) => null);
  }

  /// Jumps the scroll position of all linked controllers to [value].
  void jumpTo(double value) {
    for (final controller in _attachedControllers) {
      controller.jumpToPage(value);
    }
  }
}

/// A scroll controller that mirrors its movements to a peer, which must also
/// be a [_LinkedScrollController].
class _LinkedScrollController extends ScrollController {
  _LinkedScrollController(this._controllers)
      : super(initialScrollOffset: _controllers.page);

  final LinkedScrollControllerGroup _controllers;

  double get page =>
      offset / (position.viewportDimension * _controllers.viewportFraction);

  @override
  void dispose() {
    _controllers._allControllers.remove(this);
    super.dispose();
  }

  @override
  void attach(ScrollPosition position) {
    assert(
        position is _LinkedScrollPosition,
        '_LinkedScrollControllers can only be used with'
        ' _LinkedScrollPositions.');
    final linkedPosition = position as _LinkedScrollPosition;
    assert(linkedPosition.owner == this,
        '_LinkedScrollPosition cannot change controllers once created.');
    super.attach(position);
  }

  @override
  _LinkedScrollPosition createScrollPosition(ScrollPhysics physics,
      ScrollContext context, ScrollPosition oldPosition) {
    return _LinkedScrollPosition(
      this,
      physics: physics,
      context: context,
      initialPage: initialScrollOffset,
      oldPosition: oldPosition,
    );
  }

  @override
  _LinkedScrollPosition get position => super.position as _LinkedScrollPosition;

  Iterable<_LinkedScrollController> get _allPeersWithClients =>
      _controllers._attachedControllers.where((peer) => peer != this);

  bool get canLinkWithPeers => _allPeersWithClients.isNotEmpty;

  Iterable<_LinkedScrollActivity> linkWithPeers(_LinkedScrollPosition driver) {
    assert(canLinkWithPeers);
    return _allPeersWithClients
        .map((peer) => peer.link(driver))
        .expand((e) => e);
  }

  Iterable<_LinkedScrollActivity> link(_LinkedScrollPosition driver) {
    assert(hasClients);
    final activities = <_LinkedScrollActivity>[];
    // ignore: prefer_final_in_for_each
    for (final position in positions.cast<_LinkedScrollPosition>()) {
      activities.add(position.link(driver));
    }
    return activities;
  }

  Future<void> animateToPage(
    double page, {
    @required Curve curve,
    @required Duration duration,
  }) async =>
      animateTo(_pageToOffset(page), curve: curve, duration: duration);
  Future<void> jumpToPage(double page) async => jumpTo(_pageToOffset(page));

  double _pageToOffset(double page) =>
      page * position.viewportDimension * _controllers.viewportFraction;
}

// Implementation details: Whenever position.setPixels or position.forcePixels
// is called on a _LinkedScrollPosition (which may happen programmatically, or
// as a result of a user action),  the _LinkedScrollPosition creates a
// _LinkedScrollActivity for each linked position and uses it to move to or jump
// to the appropriate page.
//
// When a new activity begins, the set of peer activities is cleared.
class _LinkedScrollPosition extends ScrollPositionWithSingleContext {
  _LinkedScrollPosition(
    this.owner, {
    ScrollPhysics physics,
    ScrollContext context,
    this.initialPage,
    ScrollPosition oldPosition,
  })  : assert(owner != null),
        super(
          physics: physics,
          context: context,
          initialPixels: null,
          oldPosition: oldPosition,
        );

  final _LinkedScrollController owner;
  double initialPage;

  final Set<_LinkedScrollActivity> _peerActivities = <_LinkedScrollActivity>{};

  @override
  bool applyViewportDimension(double viewportDimension) {
    final oldViewportDimension =
        hasViewportDimension ? this.viewportDimension : null;
    final result = super.applyViewportDimension(viewportDimension);
    final oldPixels = hasPixels ? pixels : null;
    final page = (oldPixels == null || oldViewportDimension == 0.0)
        ? initialPage
        : oldPixels /
            (oldViewportDimension * owner._controllers.viewportFraction);
    final newPixels =
        page * viewportDimension * owner._controllers.viewportFraction;

    if (newPixels != oldPixels) {
      correctPixels(newPixels);
      return false;
    }
    return result;
  }

  // We override hold to propagate it to all peer controllers.
  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    for (final controller in owner._allPeersWithClients) {
      controller.position._holdInternal();
    }
    return super.hold(holdCancelCallback);
  }

  // Calls hold without propagating to peers.
  void _holdInternal() {
    // Passing null to hold seems fishy, but it doesn't appear to hurt anything.
    // Revisit this if bad things happen.
    super.hold(null);
  }

  @override
  void beginActivity(ScrollActivity newActivity) {
    if (newActivity == null) {
      return;
    }
    for (final activity in _peerActivities) {
      activity.unlink(this);
    }

    _peerActivities.clear();

    super.beginActivity(newActivity);
  }

  @override
  double setPixels(double newPixels) {
    if (newPixels == pixels) {
      return 0;
    }
    updateUserScrollDirection(newPixels - pixels > 0.0
        ? ScrollDirection.forward
        : ScrollDirection.reverse);

    if (owner.canLinkWithPeers) {
      _peerActivities.addAll(owner.linkWithPeers(this));
      for (final activity in _peerActivities) {
        activity.moveTo(newPixels);
      }
    }

    return setPixelsInternal(newPixels);
  }

  double setPixelsInternal(double newPixels) {
    return super.setPixels(newPixels);
  }

  @override
  void forcePixels(double value) {
    if (value == pixels) {
      return;
    }
    updateUserScrollDirection(value - pixels > 0.0
        ? ScrollDirection.forward
        : ScrollDirection.reverse);

    if (owner.canLinkWithPeers) {
      _peerActivities.addAll(owner.linkWithPeers(this));
      for (final activity in _peerActivities) {
        activity.jumpTo(value);
      }
    }

    forcePixelsInternal(value);
  }

  void forcePixelsInternal(double value) {
    super.forcePixels(value);
  }

  _LinkedScrollActivity link(_LinkedScrollPosition driver) {
    if (this.activity is! _LinkedScrollActivity) {
      beginActivity(_LinkedScrollActivity(this));
    }
    final activity = this.activity as _LinkedScrollActivity;
    // ignore: cascade_invocations
    activity.link(driver);
    return activity;
  }

  void unlink(_LinkedScrollActivity activity) {
    _peerActivities.remove(activity);
  }

  // We override this method to make it public (overridden method is protected)
  @override
  // ignore: unnecessary_overrides
  void updateUserScrollDirection(ScrollDirection value) {
    super.updateUserScrollDirection(value);
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('owner: $owner');
  }
}

class _LinkedScrollActivity extends ScrollActivity {
  _LinkedScrollActivity(_LinkedScrollPosition delegate) : super(delegate);

  @override
  _LinkedScrollPosition get delegate => super.delegate as _LinkedScrollPosition;

  final Set<_LinkedScrollPosition> drivers = <_LinkedScrollPosition>{};

  void link(_LinkedScrollPosition driver) {
    drivers.add(driver);
  }

  void unlink(_LinkedScrollPosition driver) {
    drivers.remove(driver);
    if (drivers.isEmpty) {
      delegate?.goIdle();
    }
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  // _LinkedScrollActivity is not self-driven but moved by calls to the [moveTo]
  // method.
  @override
  double get velocity => 0;

  void moveTo(double newPixels) {
    _updateUserScrollDirection();
    delegate.setPixelsInternal(newPixels);
  }

  void jumpTo(double newPixels) {
    _updateUserScrollDirection();
    delegate.forcePixelsInternal(newPixels);
  }

  void _updateUserScrollDirection() {
    assert(drivers.isNotEmpty);
    ScrollDirection commonDirection;
    for (final driver in drivers) {
      commonDirection ??= driver.userScrollDirection;
      if (driver.userScrollDirection != commonDirection) {
        commonDirection = ScrollDirection.idle;
      }
    }
    delegate.updateUserScrollDirection(commonDirection);
  }

  @override
  void dispose() {
    for (final driver in drivers) {
      driver.unlink(this);
    }
    super.dispose();
  }
}
