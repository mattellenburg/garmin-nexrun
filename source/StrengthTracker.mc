import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Manages the strength segment: tracks user-selected exercises, accumulates
// per-exercise and session-level calorie estimates, and writes FIT data.
//
// EXERCISE LIFECYCLE:
//   IDLE  — no exercise running; displays set count and total calories.
//   ACTIVE — user chose an exercise from the menu; timer running.
//             Pressing the lap button calls stopExercise(), which closes the
//             set, calculates calories, writes FIT fields, and returns to IDLE.
//
// All exercise knowledge (names, IDs, MET values) is encapsulated here so
// adding a new exercise only requires updating the menu, properties.xml, and
// the _getMet() helper below.
class StrengthTracker {

    // -------------------------------------------------------------------------
    // Dependencies
    // -------------------------------------------------------------------------

    private var _view as NexRunView;

    // -------------------------------------------------------------------------
    // Exercise state
    // -------------------------------------------------------------------------

    // Name of the currently running exercise; null when idle.
    private var _activeExercise = null as String?;

    // System.getTimer() timestamp when the current exercise started.
    private var _exerciseStartMs = 0;

    // System.getTimer() timestamp of the most recent exercise end.
    // Pre-set to -10000 so the cooldown is immediately expired on startup.
    private var _lastExerciseEndMs = -10000;

    // -------------------------------------------------------------------------
    // Display / overlay state (read by NexRunView.onUpdate)
    // -------------------------------------------------------------------------

    // Number of exercises completed in this strength segment.
    // Reset when the user leaves and re-enters Strength via resetDisplayState().
    private var _setCount = 0;

    // Name of the most recently completed exercise shown on the lap screen.
    public var _lastExerciseType = "";

    // True while the post-exercise overlay is visible.
    public var _showingSetOverlay = false;

    // Seconds remaining before the overlay auto-dismisses.
    public var _setOverlayTimer = 0;

    // -------------------------------------------------------------------------
    // Calorie accumulators
    // -------------------------------------------------------------------------

    // Running totals for the current segment (reset by resetDisplayState).
    private var _segmentCalories = 0.0f;

    // Lap-scoped total; reset by resetLap() when addLap() fires.
    private var _lapCalories = 0.0f;

    // User body weight in kg; used in the MET calorie formula.
    private var _userWeightKg = 68.04f;

    // -------------------------------------------------------------------------
    // FIT contributor field references (set by NexRunView.setupFitFields)
    // -------------------------------------------------------------------------
    // These are the LAP/SESSION fields that accumulate totals.
    // RECORD fields for exercise ID and per-set calories live in NexRunView
    // and are written directly from _writeSetResults().

    // -------------------------------------------------------------------------

    function initialize(view as NexRunView) {
        _view = view;

        // Pull body weight from the user profile if available.
        var profile = UserProfile.getProfile();
        if (profile != null && profile.weight != null) {
            _userWeightKg = profile.weight / 1000.0f;
        }
    }

    // -------------------------------------------------------------------------
    // Display data (consumed by LapDisplay via NexRunView._getActiveTracker)
    // -------------------------------------------------------------------------

    // Returns the lap-screen data dictionary for the strength segment.
    // When an exercise is running the display shows the active exercise name
    // and elapsed time so the user can see progress at a glance.
    // When idle it shows completed set count and total segment calories.
    function getDisplayData(info, lapDistM as Float) as Dictionary {
        if (_activeExercise != null) {
            // Active exercise: show name and elapsed seconds.
            var elapsedSec = (System.getTimer() - _exerciseStartMs) / 1000;
            return {
                :valueL => CommonDisplay.formatTime(elapsedSec),
                :labelL => _activeExercise,
                :valueR => null,
                :labelR => null,
            };
        }

        // Idle: show set count and accumulated segment calories.
        var calStr = _segmentCalories.format("%.1f") + " kcal";
        var exLabel = _lastExerciseType.equals("") ? "Ready" : _lastExerciseType;
        return {
            :valueL => _setCount.toString() + " sets",
            :labelL => exLabel,
            :valueR => null,
            :labelR => calStr,
        };
    }

    // -------------------------------------------------------------------------
    // Exercise lifecycle — called from NexRunMenuDelegate and NexRunDelegate
    // -------------------------------------------------------------------------

    // Starts tracking the named exercise.  Called when the user selects an
    // exercise from the sub-menu.  Plays an entry tone so the user knows the
    // timer has started even while looking away from the watch.
    public function startExercise(name as String) as Void {
        // Enforce post-exercise cooldown to prevent accidental double-starts.
        var cooldownMs = _getPostSetCooldownMs();
        if (System.getTimer() - _lastExerciseEndMs < cooldownMs) {
            return;
        }

        _activeExercise = name;
        _exerciseStartMs = System.getTimer();

        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_HI);
        }
        WatchUi.requestUpdate();
    }

    // Stops the running exercise, writes FIT data, and returns to idle.
    // Called when the user presses the lap button while an exercise is active,
    // or when leaving Strength mode entirely (e.g. switching segments).
    // Safe to call when no exercise is running — returns immediately.
    public function stopExercise() as Void {
        if (_activeExercise == null) {
            return;
        }

        var durationSec = (System.getTimer() - _exerciseStartMs).toFloat() / 1000.0f;
        _writeSetResults(_activeExercise, durationSec);

        _setCount++;
        _lastExerciseType = _activeExercise;
        _lastExerciseEndMs = System.getTimer();
        _activeExercise = null;

        // Start the post-exercise overlay countdown.
        _showingSetOverlay = true;
        _setOverlayTimer = _getSetOverlaySeconds();

        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_LO);
        }
        WatchUi.requestUpdate();
    }

    // Returns true while an exercise timer is running.
    // NexRunDelegate uses this to decide whether the lap button should stop
    // the exercise rather than open the segment menu.
    public function isExerciseActive() as Boolean {
        return _activeExercise != null;
    }

    // Returns the name of the active exercise, or null if idle.
    public function getActiveExerciseName() as String? {
        return _activeExercise;
    }

    // -------------------------------------------------------------------------
    // Per-second tick — called from NexRunView.onUpdate on the UI thread
    // -------------------------------------------------------------------------

    // Decrements the post-exercise overlay countdown each second.
    // Must run on the UI thread; NexRunView.onUpdate() calls this when the
    // timer state is TIMER_STATE_ON and the current mode is Strength.
    public function tick() as Void {
        if (_showingSetOverlay && _setOverlayTimer > 0) {
            _setOverlayTimer--;
            if (_setOverlayTimer <= 0) {
                _showingSetOverlay = false;
            }
            WatchUi.requestUpdate();
        }
    }

    // -------------------------------------------------------------------------
    // FIT field writes
    // -------------------------------------------------------------------------

    // Calculates calories, writes per-set RECORD fields, and updates running
    // SESSION / LAP calorie totals.  All field handles are null-guarded.
    private function _writeSetResults(name as String, durationSec as Float) as Void {
        var met    = _getMet(name);
        var id     = _getExerciseId(name);

        // MET calorie formula: kcal = MET × 3.5 × weightKg / 200 × durationMin
        var kcal = (met * 3.5f * _userWeightKg / 200.0f) * (durationSec / 60.0f);

        // --- RECORD fields (IDs 0–2): written once then cleared next tick ---
        // exercise_id (0) and set_calories (1) use the pending-clear pattern
        // to guarantee a non-zero value appears in the FIT file before zeroing.
        if (_view._exerciseField != null) {
            _view._exerciseField.setData(id);
        }
        if (_view._setCalField != null) {
            _view._setCalField.setData(kcal);
        }
        if (_view._setDurationField != null) {
            _view._setDurationField.setData(durationSec);
        }

        // Signal NexRunView to zero the RECORD fields on the next timer tick
        // (one FIT record later) so the values are flushed before clearing.
        _view._pendingSnapClear = true;

        // Accumulate running totals.
        _segmentCalories += kcal;
        _lapCalories     += kcal;
        _view.updateTotalCalories(kcal);
    }

    // -------------------------------------------------------------------------
    // MET lookup — reads live from Application.Properties so the user can
    // adjust values in Garmin Connect Mobile without reinstalling the app.
    // Each property stores MET × 10 as an integer; divide by 10 for the float.
    // -------------------------------------------------------------------------

    private function _getMet(name as String) as Float {
        var key = _metKeyForName(name);
        if (key != null) {
            var raw = Application.Properties.getValue(key);
            if (raw != null) {
                return (raw as Number).toFloat() / 10.0f;
            }
        }
        return 5.0f; // Conservative default for unrecognised exercise names
    }

    // Maps an exercise display name to its properties.xml MET key.
    private function _metKeyForName(name as String) as String? {
        if (name.equals("Battle Ropes"))         { return "metBattleRopes"; }
        if (name.equals("Burpees"))              { return "metBurpees"; }
        if (name.equals("Dips"))                 { return "metDips"; }
        if (name.equals("Kettlebell Swings"))    { return "metKettleBellSwings"; }
        if (name.equals("Med Ball Throws"))      { return "metMedBallThrows"; }
        if (name.equals("Monkey Bars"))          { return "metMonkeyBars"; }
        if (name.equals("Mountain Climbers"))    { return "metMtnClimbers"; }
        if (name.equals("Pull-ups"))             { return "metPullups"; }
        if (name.equals("Push-ups"))             { return "metPushups"; }
        if (name.equals("Rope Climb"))           { return "metRopeClimb"; }
        if (name.equals("Sled Push/Pull"))       { return "metSledPushPull"; }
        if (name.equals("Sledgehammer"))         { return "metSledgeHammer"; }
        if (name.equals("Tire Flips"))           { return "metTireFlips"; }
        return null;
    }

    // Returns the stable integer ID written to the FIT exercise_id field.
    // IDs must not be renumbered once an activity has been recorded.
    private function _getExerciseId(name as String) as Number {
        if (name.equals("Battle Ropes"))         { return 1; }
        if (name.equals("Burpees"))              { return 2; }
        if (name.equals("Dips"))                 { return 3; }
        if (name.equals("Kettlebell Swings"))    { return 4; }
        if (name.equals("Med Ball Throws"))      { return 5; }
        if (name.equals("Monkey Bars"))          { return 6; }
        if (name.equals("Mountain Climbers"))    { return 7; }
        if (name.equals("Pull-ups"))             { return 8; }
        if (name.equals("Push-ups"))             { return 9; }
        if (name.equals("Rope Climb"))           { return 10; }
        if (name.equals("Sled Push/Pull"))       { return 11; }
        if (name.equals("Sledgehammer"))         { return 12; }
        if (name.equals("Tire Flips"))           { return 13; }
        return 0;
    }

    // -------------------------------------------------------------------------
    // Property helpers — null-safe reads with sensible defaults
    // -------------------------------------------------------------------------

    private function _getSetOverlaySeconds() as Number {
        var v = Application.Properties.getValue("stSetOverlaySeconds");
        return v != null ? v as Number : 5;
    }

    private function _getPostSetCooldownMs() as Number {
        var v = Application.Properties.getValue("stPostSetCooldownMs");
        return v != null ? v as Number : 2000;
    }

    // -------------------------------------------------------------------------
    // Reset helpers
    // -------------------------------------------------------------------------

    // Resets display counters when the user re-enters Strength mode so the
    // screen starts at "0 sets / Ready" rather than showing stale values.
    public function resetDisplayState() as Void {
        _setCount          = 0;
        _lastExerciseType  = "";
        _segmentCalories   = 0.0f;
        _showingSetOverlay = false;
        _setOverlayTimer   = 0;
    }

    // Zeroes the lap-scoped calorie accumulator.
    // Called by NexRunView after addLap() so each lap starts from zero.
    public function resetLap() as Void {
        _lapCalories = 0.0f;
    }

    // Returns the total calories burned in this strength segment (for display).
    public function getSegmentCalories() as Float {
        return _segmentCalories;
    }
}
