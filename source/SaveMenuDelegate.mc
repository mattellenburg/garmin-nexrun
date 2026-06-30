import Toybox.Activity;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// Handles the Save / Resume / Discard menu shown after the activity is stopped.
// Receives both the session and the view so that on Resume it can re-apply the
// correct timer state for the current segment (Strength and Rest segments keep
// the session timer paused; all others resume it), and on Save it can capture
// final stats for the post-save summary screen.
class SaveMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _session;
    private var _view as NexRunView;

    function initialize(session, view as NexRunView) {
        Menu2InputDelegate.initialize();
        _session = session;
        _view    = view;
    }

    function onSelect(item) {
        var id = item.getId();

        if (id.equals("resume")) {
            // Re-apply the correct timer state for whatever segment was active
            // when the user hit stop.  Strength and Rest segments must remain
            // paused; all others should have the timer running.
            var mode = (_view as NexRunView)._currentMode;
            var shouldRun = (mode == $.STATE_WARMUP   ||
                             mode == $.STATE_CARDIO   ||
                             mode == $.STATE_COOLDOWN ||
                             mode == $.STATE_STRETCHING);
            if (shouldRun) {
                _session.start();
            }
            // For Strength/Rest the session was already stopped and stays that
            // way; no call needed.  The user will resume the timer naturally
            // when they next switch to a running-type segment.
            WatchUi.popView(WatchUi.SLIDE_DOWN);

        } else if (id.equals("save")) {
            // Capture the headline stats BEFORE save() so the summary screen
            // has reliable data regardless of session state after saving.
            var stats = _captureFinalStats();
            _session.save();
            WatchUi.switchToView(
                new ActivitySummaryView(stats),
                new ActivitySummaryDelegate(),
                WatchUi.SLIDE_UP);

        } else if (id.equals("discard")) {
            _session.discard();
            System.exit();
        }
    }

    // Gathers the four headline stats shown on the post-save summary screen.
    // Distance and calories come from the live ActivityInfo snapshot; time is
    // taken the same way the in-app Totals page computes it.
    private function _captureFinalStats() as Dictionary {
        var info = Activity.getActivityInfo();
        var totalTimeMs    = info != null && info.timerTime != null        ? info.timerTime        : 0;
        var totalDistMiles = info != null && info.elapsedDistance != null  ? info.elapsedDistance * 0.000621371 : 0.0;
        var totalCalories  = info != null && info.calories != null         ? info.calories         : 0;
        var avgHR          = info != null && info.averageHeartRate != null ? info.averageHeartRate : 0;

        return {
            :totalTimeMs    => totalTimeMs,
            :totalDistMiles => totalDistMiles,
            :totalCalories  => totalCalories,
            :avgHR          => avgHR,
        };
    }
}
