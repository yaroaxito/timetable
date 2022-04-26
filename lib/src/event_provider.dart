import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:time_machine/time_machine.dart';

import 'controller.dart';
import 'event.dart';

/// Provides [Event]s to a [TimetableController].
///
/// We provide the following implementations:
/// - [EventProvider.list], if you have a non-changing list of [Event]s.
/// - [EventProvider.simpleStream], if you have a changing list of [Event]s.
/// - [EventProvider.stream], if your events may change or you have many events
///   and only want to load a relevant subset.
abstract class EventProvider<E extends Event> {
  const EventProvider();

  /// Creates an [EventProvider] based on a fixed list of [Event]s.
  ///
  /// See also:
  /// - [EventProvider]'s class comment for an overview of provided
  ///   implementations.
  factory EventProvider.list(List<E> events) = ListEventProvider<E>;

  /// Creates an [EventProvider] accepting a [Stream] of [Event]s.
  ///
  /// See also:
  /// - [EventProvider]'s class comment for an overview of provided
  ///   implementations.
  factory EventProvider.simpleStream(Stream<List<E>> eventStream) {
    assert(eventStream != null);

    final baseStream = eventStream.publishValue();
    final subscription = baseStream.connect();
    return EventProvider<E>.stream(
      eventGetter: (dates) {
        return baseStream.map((e) {
          return e.intersectingInterval(dates);
        });
      },
      onDispose: subscription.cancel,
    );
  }

  /// Creates an [EventProvider] accepting a [Stream] of [Event]s based on the
  /// currently visible range.
  ///
  /// See also:
  /// - [EventProvider]'s class comment for an overview of provided
  ///   implementations.
  factory EventProvider.stream({
    @required StreamedEventGetter<E> eventGetter,
    VoidCallback onDispose,
  }) = StreamEventProvider<E>;

  void onVisibleDatesChanged(DateInterval visibleRange) {}

  Stream<Iterable<E>> getAllDayEventsIntersecting(DateInterval interval);
  Stream<Iterable<E>> getPartDayEventsIntersecting(LocalDate date);

  /// Discards any resources used by the object.
  ///
  /// After this is called, the object is not in a usable state and should be
  /// discarded.
  ///
  /// This method is usually called by [TimetableController].
  void dispose() {}
}

/// An [EventProvider] accepting a single, non-changing list of [Event]s.
///
/// See also:
/// - [EventProvider.simpleStream], if you have a few events, but they may
///   change.
/// - [EventProvider.stream], if your events change or you have lots of them.
class ListEventProvider<E extends Event> extends EventProvider<E> {
  ListEventProvider(List<E> events)
      : assert(events != null),
        _events = events;

  final List<E> _events;

  @override
  Stream<Iterable<E>> getAllDayEventsIntersecting(DateInterval interval) {
    final events = _events.allDayEvents.intersectingInterval(interval);
    return Stream.value(events);
  }

  @override
  Stream<Iterable<E>> getPartDayEventsIntersecting(LocalDate date) {
    final events = _events.partDayEvents.intersectingDate(date);
    return Stream.value(events);
  }
}

mixin VisibleDatesStreamEventProviderMixin<E extends Event>
    on EventProvider<E> {
  final _visibleDates = BehaviorSubject<DateInterval>();
  ValueStream<DateInterval> get visibleDates => _visibleDates.stream;

  @mustCallSuper
  @override
  void onVisibleDatesChanged(DateInterval visibleRange) {
    _visibleDates.add(visibleRange);
  }

  @mustCallSuper
  @override
  void dispose() {
    _visibleDates.close();
  }
}

typedef StreamedEventGetter<E extends Event> = Stream<Iterable<E>> Function(
    DateInterval dates);

/// An [EventProvider] accepting a [Stream] of [Event]s based on the currently
/// visible range.
///
/// See also:
/// - [EventProvider.list], if you only have a few static [Event]s.
/// - [EventProvider.simpleStream], if you only have a few events that may
///   change.
class StreamEventProvider<E extends Event> extends EventProvider<E>
    with VisibleDatesStreamEventProviderMixin<E> {
  StreamEventProvider({@required this.eventGetter, this.onDispose})
      : assert(eventGetter != null) {
    _events = visibleDates.switchMap(eventGetter).publishValue();
    _eventsSubscription = _events.connect();
  }

  final StreamedEventGetter<E> eventGetter;
  final VoidCallback onDispose;

  ValueConnectableStream<Iterable<E>> _events;
  StreamSubscription<Iterable<E>> _eventsSubscription;

  @override
  Stream<Iterable<E>> getAllDayEventsIntersecting(DateInterval interval) {
    return _events
        .map((events) => events.allDayEvents.intersectingInterval(interval));
  }

  @override
  Stream<Iterable<E>> getPartDayEventsIntersecting(LocalDate date) {
    return _events.map((events) => events.partDayEvents.intersectingDate(date));
  }

  @override
  void dispose() {
    _eventsSubscription.cancel();
    onDispose?.call();
    super.dispose();
  }
}
