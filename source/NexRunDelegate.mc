import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.WatchUi;

// Handles all button input on the main NexRun watch face.
//
// BUTTON MAP (Fenix 6 Pro):
//   Start/Stop (GPS) — onSelect:
//     • Activity not started  → start the activity
//     • Summary overlay shown → dismiss it
//     • Strength + exercise running → stop that exercise, return to Strength idle
//     • Any other state → stop activity, show Save menu
//
//   Up / Down (onKey) → scroll data pages; any press also dismisses a summary
//
//   Back → open the segment-switcher menu (shows summary overlay while open)
//
//   Power/Menu → stop activity and show Save menu (reachable from all segments)
class NexRunDelegate extends WatchUi.BehaviorDelegate {

    private var _view    as NexRunView;
    private var _session as ActivityRecording.Session? = null;

    function initialize(view as NexRunView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // -------------------------------------------------------------------------
    // Start/Stop (GPS) button
    // -------------------------------------------------------------------------

    function onSelect() as Boolean {
        var v = _view as NexRunView;

        // 1. Dismiss the summary overlay if it is showing.
        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer   = 0;
            WatchUi.requestUpdate();
            return true;
        }

        // 2. Start the activity if no session is running yet.
        if (_session == null || !_session.isRecording()) {
            _startActivity();
            return true;
        }

        // 3. Strength mode with an exercise running → stop just that exercise.
        //    The lap button acts as a "stop set" shortcut so the user does not
        //    need to navigate the menu while their heart rate is elevated.
        if (v._currentMode == $.STATE_STRENGTH &&
            v._strengthTracker.isExerciseActive()) {
            v._strengthTracker.stopExercise();
            return true;
        }

        // 4. All other states → stop the entire activity.
        // Ensure any in-progress strength exercise is closed before stopping
        // so its FIT data is written.
        if (v._currentMode == $.STATE_STRENGTH) {
            v._strengthTracker.stopExercise();
        }
        _session.stop();
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_STOP);
        }
        _pushSaveMenu();
        return true;
    }

    // Creates a new activity recording session and starts it immediately.
    // FIT fields are registered before start() so no records are missed.
    private function _startActivity() as Void {
        if (_session == null) {
            _session = ActivityRecording.createSession({
                :name     => "NexRun",
                :sport    => Activity.SPORT_RUNNING,
                :subSport => Activity.SUB_SPORT_GENERIC,
            });
            _view.setupFitFields(_session);
        }

        if (!_session.isRecording()) {
            _session.start();
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_START);
            }
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 200)]);
            }
        }
        WatchUi.requestUpdate();
    }

    // -------------------------------------------------------------------------
    // Up / Down keys — page scrolling
    // -------------------------------------------------------------------------

    function onKey(evt) as Boolean {
        var v = _view as NexRunView;

        // Any key press dismisses the summary overlay first.
        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer   = 0;
            WatchUi.requestUpdate();
            return true;
        }

        var key = evt.getKey();
        if (key == WatchUi.KEY_DOWN) { _view.nextPage();     return true; }
        if (key == WatchUi.KEY_UP)   { _view.previousPage(); return true; }
        return false;
    }

    // -------------------------------------------------------------------------
    // Back button — segment switcher
    // -------------------------------------------------------------------------

    // Opens the segment menu.  If the summary overlay is showing, it is
    // dismissed instead so the user can see the watch face before switching.
    function onBack() as Boolean {
        var v = _view as NexRunView;

        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer   = 0;
            WatchUi.requestUpdate();
            return true;
        }

        // Capture current average HR for the summary overlay that the menu
        // delegate will display after the segment switch.
        var info = Activity.getActivityInfo();
        v._lastAvgHR = (info != null && info.averageHeartRate != null)
                       ? info.averageHeartRate : 0;

        // Show the summary overlay while the menu is open so the display isn't
        // blank if the user immediately cancels the menu.
        v._showingSummary = true;
        v._summaryTimer   = 30;

        return _pushSegmentMenu();
    }

    // -------------------------------------------------------------------------
    // Power / Menu button — stop activity
    // -------------------------------------------------------------------------

    // On the Fenix 6 Pro the power/light key fires onMenu while recording.
    // This is the only reliable path to the Save menu from every segment,
    // including Strength with an exercise running.
    function onMenu() as Boolean {
        if (_session == null || !_session.isRecording()) { return false; }

        // Cleanly close any running exercise before stopping.
        var v = _view as NexRunView;
        if (v._currentMode == $.STATE_STRENGTH) {
            v._strengthTracker.stopExercise();
        }

        _session.stop();
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_STOP);
        }
        _pushSaveMenu();
        return true;
    }

    // -------------------------------------------------------------------------
    // Gesture-based page scrolling (touch / swipe on compatible devices)
    // -------------------------------------------------------------------------

    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

    // -------------------------------------------------------------------------
    // Menu builders
    // -------------------------------------------------------------------------

    // Segment-switcher menu.  When in Strength mode an extra "Exercise" item
    // is inserted at the top so the user can pick an exercise without leaving
    // the Strength segment.
    private function _pushSegmentMenu() as Boolean {
        var v    = _view as NexRunView;
        var menu = new WatchUi.Menu2({ :title => "Switch To:" });

        // "Exercise" is only offered while in Strength so the menu stays short
        // in all other segments and the option is contextually obvious.
        if (v._currentMode == $.STATE_STRENGTH) {
            menu.addItem(new WatchUi.MenuItem(
                "Exercise", "Pick an exercise", "exercise", null));
        }

        menu.addItem(new WatchUi.MenuItem("Warmup",    "Warmup Phase",    "warmup",     null));
        menu.addItem(new WatchUi.MenuItem("Cardio",    "Moving Phase",    "cardio",     null));
        menu.addItem(new WatchUi.MenuItem("Rest",      "Recovery Phase",  "rest",       null));
        menu.addItem(new WatchUi.MenuItem("Strength",  "Strength Phase",  "strength",   null));
        menu.addItem(new WatchUi.MenuItem("Cool Down", "Cool Down Phase", "cooldown",   null));
        menu.addItem(new WatchUi.MenuItem("Stretching","Recovery Phase",  "stretching", null));

        WatchUi.pushView(menu,
            new NexRunMenuDelegate(_view, _session),
            WatchUi.SLIDE_UP);
        return true;
    }

    // Save / Resume / Discard menu shown after the activity is stopped.
    private function _pushSaveMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Paused" });
        menu.addItem(new WatchUi.MenuItem("Resume",  null, "resume",  null));
        menu.addItem(new WatchUi.MenuItem("Save",    null, "save",    null));
        menu.addItem(new WatchUi.MenuItem("Discard", null, "discard", null));

        WatchUi.pushView(menu,
            new SaveMenuDelegate(_session),
            WatchUi.SLIDE_UP);
    }
}
