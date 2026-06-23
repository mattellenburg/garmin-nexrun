import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Handles all button input on the main NexRun watch face.
//
// BUTTON MAP (Fenix 6 Pro):
//   Start/Stop (GPS):
//     • Activity not started           → start the activity
//     • Summary overlay showing        → dismiss it
//     • Strength + exercise running    → stop that exercise (return to Strength idle)
//     • Any other state                → stop activity, show Save menu
//
//   Up / Down → scroll data pages; also dismisses the summary overlay
//
//   Back (single press) → open segment-switcher menu
//   Back (double press, ≤800 ms between presses) → instant rest shortcut:
//     • In Strength mode  → start an in-strength Rest interval (no calories)
//     • All other modes   → switch immediately to the Rest segment
//
//   Power/Menu → stop activity, show Save menu
class NexRunDelegate extends WatchUi.BehaviorDelegate {
    private var _view as NexRunView;
    private var _session as ActivityRecording.Session? = null;

    // True once the activity has been started at least once, so we can
    // distinguish a paused session from one that was never started.
    private var _activityStarted = false;

    // System.getTimer() value of the most recent Back press.  Used to detect
    // a double press within DOUBLE_PRESS_WINDOW_MS.
    private var _lastBackPressMs = -10000;
    private const DOUBLE_PRESS_WINDOW_MS = 800;

    function initialize(view as NexRunView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // ---- Start/Stop (GPS) button ----

    function onSelect() as Boolean {
        var v = _view as NexRunView;

        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer = 0;
            WatchUi.requestUpdate();
            return true;
        }

        if (!_activityStarted || _session == null || !_session.isRecording()) {
            _startActivity();
            return true;
        }

        // Strength + exercise active → stop the exercise, not the whole activity.
        if (
            v._currentMode == $.STATE_STRENGTH &&
            v._strengthTracker.isExerciseActive()
        ) {
            v._strengthTracker.stopExercise();
            return true;
        }

        // All other cases → end the activity.
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

    // Creates and starts the recording session.  FIT fields are registered
    // before start() so no RECORD rows are missed.
    private function _startActivity() as Void {
        if (_session == null) {
            _session = ActivityRecording.createSession({
                :name => "NexRun",
                :sport => Activity.SPORT_RUNNING,
                :subSport => Activity.SUB_SPORT_GENERIC,
            });
            _view.setupFitFields(_session);
        }
        if (!_session.isRecording()) {
            _session.start();
            _activityStarted = true;
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_START);
            }
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 200)]);
            }
        }
        WatchUi.requestUpdate();
    }

    // ---- Up / Down keys — page scrolling ----

    function onKey(evt) as Boolean {
        var v = _view as NexRunView;
        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer = 0;
            WatchUi.requestUpdate();
            return true;
        }
        var key = evt.getKey();
        if (key == WatchUi.KEY_DOWN) {
            _view.nextPage();
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            _view.previousPage();
            return true;
        }
        return false;
    }

    // ---- Back button — segment switcher / double-press rest shortcut ----

    // Single Back press: open the segment-switcher menu (with summary overlay
    // visible behind it so the display isn't blank if the user cancels).
    //
    // Double Back press (within DOUBLE_PRESS_WINDOW_MS): skip the menu and
    // enter a rest state immediately.  In Strength mode this starts an
    // in-strength rest interval; in all other modes it switches to the Rest
    // segment and adds a FIT lap marker.
    function onBack() as Boolean {
        var v = _view as NexRunView;

        // Summary overlay takes priority — dismiss it on any Back press.
        if (v._showingSummary) {
            v._showingSummary = false;
            v._summaryTimer = 0;
            WatchUi.requestUpdate();
            return true;
        }

        var now = System.getTimer();
        var delta = now - _lastBackPressMs;
        _lastBackPressMs = now;

        if (delta < DOUBLE_PRESS_WINDOW_MS) {
            // Double press detected — execute the rest shortcut.
            _doRestShortcut();
            return true;
        }

        // Single press — show the segment name overlay behind the menu so
        // there's never a blank screen if the user opens and immediately cancels.
        v._showingSummary = true;
        v._summaryTimer = 3;
        return _pushSegmentMenu();
    }

    // Enters a rest state without opening the menu.
    // In Strength: starts an in-strength rest interval (zero-calorie timer).
    // Elsewhere: writes a lap marker, resets lap stats, and switches to Rest.
    private function _doRestShortcut() as Void {
        var v = _view as NexRunView;

        if (v._currentMode == $.STATE_STRENGTH) {
            // If an exercise is already running, stop it first so the timer
            // doesn't keep accumulating calories while the user rests.
            if (v._strengthTracker.isExerciseActive()) {
                v._strengthTracker.stopExercise();
            }
            v._strengthTracker.startExercise("Rest");
            return;
        }

        // For non-Strength segments, switch to the Rest segment with a lap marker.
        if (_session != null && _session.isRecording()) {
            _session.addLap();
            v._strengthTracker.resetLap();
            v.resetLapStats();
        }

        // Pause the timer: Rest segment excludes time from the pace calculation.
        _applyTimerStateForMode($.STATE_REST);

        v._showingSummary = true;
        v._summaryTimer = 3;

        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            v._lapStartTime = info.timerTime;
            if (info.elapsedDistance != null) {
                v._lapStartDistance = info.elapsedDistance;
            }
        }

        v.setMode($.STATE_REST);
        WatchUi.requestUpdate();
    }

    // ---- Power / Menu button — stop activity ----

    function onMenu() as Boolean {
        if (_session == null || !_activityStarted) {
            return false;
        }
        var v = _view as NexRunView;
        if (v._currentMode == $.STATE_STRENGTH) {
            v._strengthTracker.stopExercise();
        }
        // Ensure session is recording before calling stop(), since it may be
        // paused (timer stopped for a Strength/Rest segment).
        if (_session.isRecording()) {
            _session.stop();
        }
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_STOP);
        }
        _pushSaveMenu();
        return true;
    }

    // ---- Gesture-based page scrolling ----

    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }
    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

    // ---- Session timer management ----

    // Pauses or resumes the session timer based on the target segment.
    // Strength and Rest segments pause the timer so their time is excluded
    // from the FIT session avg_speed (and therefore from Connect's avg pace).
    // All other segments keep the timer running.
    public function applyTimerStateForMode(newMode as Number) as Void {
        _applyTimerStateForMode(newMode);
    }

    private function _applyTimerStateForMode(newMode as Number) as Void {
        if (_session == null || !_activityStarted) {
            return;
        }
        var shouldRun =
            newMode == $.STATE_WARMUP ||
            newMode == $.STATE_CARDIO ||
            newMode == $.STATE_COOLDOWN ||
            newMode == $.STATE_STRETCHING;
        if (shouldRun && !_session.isRecording()) {
            _session.start(); // Resume timer
        } else if (!shouldRun && _session.isRecording()) {
            _session.stop(); // Pause timer (not a full stop — session stays alive)
        }
    }

    // ---- Menu builders ----

    private function _pushSegmentMenu() as Boolean {
        var v = _view as NexRunView;
        var menu = new WatchUi.Menu2({ :title => "Switch To:" });
        if (v._currentMode == $.STATE_STRENGTH) {
            menu.addItem(
                new WatchUi.MenuItem(
                    "Exercise",
                    "Pick an exercise",
                    "exercise",
                    null
                )
            );
        }
        menu.addItem(
            new WatchUi.MenuItem("Rest", "Recovery Phase", "rest", null)
        );
        menu.addItem(
            new WatchUi.MenuItem("Cardio", "Moving Phase", "cardio", null)
        );
        menu.addItem(
            new WatchUi.MenuItem("Strength", "Strength Phase", "strength", null)
        );
        menu.addItem(
            new WatchUi.MenuItem(
                "Cool Down",
                "Cool Down Phase",
                "cooldown",
                null
            )
        );
        menu.addItem(
            new WatchUi.MenuItem(
                "Stretching",
                "Recovery Phase",
                "stretching",
                null
            )
        );
        menu.addItem(
            new WatchUi.MenuItem("Warmup", "Warmup Phase", "warmup", null)
        );

        WatchUi.pushView(
            menu,
            new NexRunMenuDelegate(_view, _session, self),
            WatchUi.SLIDE_UP
        );
        return true;
    }

    private function _pushSaveMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Paused" });
        menu.addItem(new WatchUi.MenuItem("Resume", null, "resume", null));
        menu.addItem(new WatchUi.MenuItem("Save", null, "save", null));
        menu.addItem(new WatchUi.MenuItem("Discard", null, "discard", null));
        WatchUi.pushView(
            menu,
            new SaveMenuDelegate(_session, _view),
            WatchUi.SLIDE_UP
        );
    }
}
