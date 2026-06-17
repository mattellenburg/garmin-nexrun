import Toybox.Lang;

// Cardio segment tracker.
// Returns lap pace (left), lap distance (right), and overall cardio-only pace
// (bottom) so the user can see both their current effort and session average.
class CardioTracker {

    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        _view = view;
    }

    function reset() as Void {}

    function getDisplayData(info, lapDistM as Float) as Dictionary {
        // Get the standard lap pace + distance from the shared helper.
        var base = _view.getRunningUnits(info, lapDistM);

        // Append the overall cardio-only average pace as the bottom field.
        // This is computed from _runTimeSec/_runDistanceM which accumulate only
        // while in Cardio mode and the user is actually moving (>0.2 m/s).
        var overallPace = "--:--";
        if (_view._runTimeSec > 0 && _view._runDistanceM > 0) {
            var avgSpeedMps = _view._runDistanceM / _view._runTimeSec;
            var settings    = Toybox.System.getDeviceSettings();
            var isMetric    = settings.distanceUnits == Toybox.System.UNIT_METRIC;
            var divisor     = isMetric ? 1000.0 : 1609.34;
            var secPer      = (divisor / avgSpeedMps).toNumber();
            overallPace     = CommonDisplay.formatTime(secPer);
        }

        base[:valueB] = overallPace;
        base[:labelB] = "AVG PACE";
        return base;
    }
}
