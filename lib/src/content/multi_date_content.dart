import 'package:black_hole_flutter/black_hole_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:time_machine/time_machine.dart';

import '../controller.dart';
import '../date_page_view.dart';
import '../event.dart';
import '../theme.dart';
import '../timetable.dart';
import '../utils/stream_change_notifier.dart';
import 'current_time_indicator_painter.dart';
import 'multi_date_background_painter.dart';
import 'streamed_date_events.dart';

class MultiDateContent<E extends Event> extends StatefulWidget {
  const MultiDateContent({
    Key key,
    @required this.controller,
    @required this.eventBuilder,
    this.onEventBackgroundTap,
  })  : assert(controller != null),
        assert(eventBuilder != null),
        super(key: key);

  final TimetableController<E> controller;
  final EventBuilder<E> eventBuilder;
  final OnEventBackgroundTapCallback onEventBackgroundTap;

  @override
  _MultiDateContentState<E> createState() => _MultiDateContentState<E>();
}

class _MultiDateContentState<E extends Event>
    extends State<MultiDateContent<E>> {
  final _timeListenable =
      StreamChangeNotifier(Stream<void>.periodic(Duration(seconds: 10)));

  @override
  void dispose() {
    _timeListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final timetableTheme = context.timetableTheme;
    return CustomPaint(
      painter: MultiDateBackgroundPainter(
        controller: widget.controller,
        dividerColor: timetableTheme?.dividerColor ?? theme.dividerColor,
      ),
      foregroundPainter: CurrentTimeIndicatorPainter(
        controller: widget.controller,
        color: timetableTheme?.timeIndicatorColor ??
            theme.highEmphasisOnBackground,
      ),
      child: DatePageView(
        controller: widget.controller,
        builder: (_, date) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: widget.onEventBackgroundTap != null
                    ? (details) {
                        _callOnEventBackgroundTap(details, date, constraints);
                      }
                    : null,
                child: StreamedDateEvents<E>(
                  date: date,
                  controller: widget.controller,
                  eventBuilder: widget.eventBuilder,
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _callOnEventBackgroundTap(
    TapUpDetails details,
    LocalDate date,
    BoxConstraints constraints,
  ) {
    final millis = details.localPosition.dy /
        constraints.maxHeight *
        TimeConstants.millisecondsPerDay;
    final time = LocalTime.sinceMidnight(Time(milliseconds: millis.floor()));
    widget.onEventBackgroundTap(date.at(time), false);
  }
}
