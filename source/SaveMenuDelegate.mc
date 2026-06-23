import Toybox.WatchUi;
import Toybox.System;

// Handles the Save / Resume / Discard menu shown after the activity is stopped.
// Receives both the session and the view so that on Resume it can re-apply the
// correct timer state for the current segment (Strength and Rest segments keep
// the session timer paused; all others resume it).
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
            _session.save();
            System.exit();

        } else if (id.equals("discard")) {
            _session.discard();
            System.exit();
        }
    }
}
