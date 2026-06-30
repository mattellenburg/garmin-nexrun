import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Manages the strength segment: tracks user-selected exercises, accumulates
// per-exercise and session-level calorie estimates, and writes FIT data.
//
// EXERCISE LIFECYCLE:
//   IDLE   — no exercise running; displays set count and total calories.
//   ACTIVE — user chose an exercise from the menu; timer running.
//             Start/Stop button calls stopExercise(), which closes the
//             set, calculates calories (unless it was a Rest interval),
//             writes FIT fields, and returns to IDLE.
//   REST   — same timer mechanic as ACTIVE but _activeIsRest is true so
//             no calories are written and no FIT RECORD fields are touched.
//             This lets the user rest between sets without leaving Strength
//             mode and without inflating the calorie total.
//
// GENERIC EXERCISE:
//   The user may select "Generic" and then choose a MET value from a sub-menu.
//   The chosen name is encoded as "Generic MET NN" where NN is MET × 10
//   (e.g. "Generic MET 80" = MET 8.0).  _getMet() parses this encoding at
//   runtime so no additional properties.xml entries are required.
//   All Generic variants share exercise_id 14 in the FIT file.
//
// All other exercise knowledge (names, IDs, MET values) is encapsulated here
// so adding a named exercise requires only: the menu entry, properties.xml,
// and one new branch each in _metKeyForName() and _getExerciseId().
class StrengthTracker {

    // -------------------------------------------------------------------------
    // Dependencies
    // -------------------------------------------------------------------------

    private var _view as NexRunView;

    // -------------------------------------------------------------------------
    // Exercise state
    // -------------------------------------------------------------------------

    // Name of the currently running exercise (or "Rest"); null when idle.
    private var _activeExercise = null as String?;

    // True when the active "exercise" is actually an in-strength rest interval.
    // When true, stopExercise() skips calorie calculation and FIT writes.
    private var _activeIsRest = false;

    // System.getTimer() timestamp when the current exercise/rest started.
    private var _exerciseStartMs = 0;

    // System.getTimer() timestamp of the most recent exercise/rest end.
    // Only meaningful once _hasEndedExercise is true (see below).
    private var _lastExerciseEndMs = 0;

    // True once at least one exercise/rest has been stopped.  The post-set
    // cooldown only exists to prevent an accidental immediate re-trigger
    // right after a real stop, so it has nothing to guard against until that
    // has happened at least once.  This avoids comparing System.getTimer()
    // against a fixed sentinel offset: System.getTimer() reflects real device
    // uptime (not app-launch-relative time) and is a 32-bit signed value, so
    // a sentinel like "construction time minus 10 seconds" can wrap negative
    // on a device that has been powered on for ~25+ days, silently blocking
    // the very first exercise of the activity with no error or tone.
    private var _hasEndedExercise = false;

    // -------------------------------------------------------------------------
    // Display / overlay state (read by NexRunView.onUpdate)
    // -------------------------------------------------------------------------

    // Number of exercises completed in this strength segment (rests excluded).
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
    //
    // Three visually distinct states, flagged via :labelColor so LapDisplay
    // can tint the primary field without knowing anything about Strength:
    //   ACTIVE EXERCISE — exercise name in RED, signaling "working".
    //   RESTING         — "RESTING" in YELLOW, signaling "recovering".  The
    //                      label reads as a state rather than the literal
    //                      exercise name "Rest" passed into startExercise().
    //   IDLE            — white, unchanged from before.
    function getDisplayData(info, lapDistM as Float) as Dictionary {
        if (_activeExercise != null) {
            var elapsedSec = (System.getTimer() - _exerciseStartMs) / 1000;
            if (_activeIsRest) {
                return {
                    :valueL     => CommonDisplay.formatTime(elapsedSec),
                    :labelL     => "RESTING",
                    :valueR     => null,
                    :labelR     => null,
                    :labelColor => Graphics.COLOR_YELLOW,
                };
            }
            return {
                :valueL     => CommonDisplay.formatTime(elapsedSec),
                :labelL     => _activeExercise,
                :valueR     => null,
                :labelR     => null,
                :labelColor => Graphics.COLOR_RED,
            };
        }

        // Idle: show completed set count and accumulated segment calories.
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

    // Starts tracking the named exercise or a rest interval.
    // Passing name = "Rest" activates rest mode: the timer runs but no
    // calories are written when the interval ends.
    // Plays an entry tone so the user knows the timer started even while
    // looking away from the watch.
    public function startExercise(name as String) as Void {
        // Enforce post-exercise cooldown to prevent accidental double-starts.
        // Skipped entirely until an exercise has actually ended once — see
        // _hasEndedExercise comment for why this can't use a sentinel timestamp.
        if (_hasEndedExercise) {
            var cooldownMs = _getPostSetCooldownMs();
            if (System.getTimer() - _lastExerciseEndMs < cooldownMs) {
                return;
            }
        }

        _activeExercise = name;
        _activeIsRest   = name.equals("Rest");
        _exerciseStartMs = System.getTimer();

        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_HI);
        }
        WatchUi.requestUpdate();
    }

    // Stops the running exercise or rest interval and returns to idle.
    //
    // For a rest interval (_activeIsRest == true):
    //   - The set counter and _lastExerciseType are NOT updated (a rest is
    //     not a set and we don't want it shown as the "last exercise").
    //   - No FIT fields are written and no calories are calculated.
    //
    // For a real exercise:
    //   - Calories are calculated via MET, FIT RECORD fields are written,
    //     the set counter increments, and the post-exercise overlay starts.
    //
    // Safe to call when no exercise is running — returns immediately.
    public function stopExercise() as Void {
        if (_activeExercise == null) {
            return;
        }

        var wasRest    = _activeIsRest;
        var name       = _activeExercise;
        var durationSec = (System.getTimer() - _exerciseStartMs).toFloat() / 1000.0f;

        // Clear active state before branching so the display reverts to idle
        // even if something below throws.
        _activeExercise    = null;
        _activeIsRest      = false;
        _lastExerciseEndMs = System.getTimer();
        _hasEndedExercise  = true;

        if (wasRest) {
            // Rest interval ended — no calories, no FIT writes, no set counted.
            // Play a neutral tone so the user knows the timer stopped.
            if (Attention has :playTone) {
                Attention.playTone(Attention.TONE_ALERT_LO);
            }
            WatchUi.requestUpdate();
            return;
        }

        // Real exercise: write FIT data, accumulate calories, update counters.
        _writeSetResults(name, durationSec);

        _setCount++;
        _lastExerciseType = name;

        // Start the post-exercise overlay countdown.
        _showingSetOverlay = true;
        _setOverlayTimer = _getSetOverlaySeconds();

        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_LO);
        }
        WatchUi.requestUpdate();
    }

    // Returns true while an exercise timer (or rest timer) is running.
    // NexRunDelegate uses this to decide whether Start/Stop should stop the
    // current exercise rather than end the entire activity.
    public function isExerciseActive() as Boolean {
        return _activeExercise != null;
    }

    // Returns true only when a genuine exercise (not a rest interval) is
    // running.  Used by NexRunDelegate to decide whether the top item of the
    // segment-switch menu should offer a quick "Rest" shortcut: that shortcut
    // only makes sense while the user is actively exercising, not while they
    // are already resting or idle in the Strength segment.
    public function isRealExerciseActive() as Boolean {
        return _activeExercise != null && !_activeIsRest;
    }

    // Returns the name of the active exercise/rest, or null if idle.
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
    // Never called for rest intervals (stopExercise() returns early for those).
    private function _writeSetResults(name as String, durationSec as Float) as Void {
        var met    = _getMet(name);
        var id     = _getExerciseId(name);

        // MET calorie formula: kcal = MET × 3.5 × weightKg / 200 × durationMin
        var kcal = (met * 3.5f * _userWeightKg / 200.0f) * (durationSec / 60.0f);

        // --- RECORD fields (IDs 0–2): written once then cleared next tick ---
        // The pending-clear pattern ensures the non-zero value is flushed by the
        // FIT SDK (which writes RECORD messages at 1 Hz) before being zeroed.
        if (_view._exerciseField != null) {
            _view._exerciseField.setData(id);
        }
        if (_view._setCalField != null) {
            _view._setCalField.setData(kcal);
        }
        if (_view._setDurationField != null) {
            _view._setDurationField.setData(durationSec);
        }

        // Signal NexRunView to zero the RECORD fields one tick later.
        _view._pendingSnapClear = true;

        // Accumulate running totals for in-app display and SESSION/LAP FIT fields.
        _segmentCalories += kcal;
        _lapCalories     += kcal;
        _view.updateTotalCalories(kcal);
    }

    // -------------------------------------------------------------------------
    // MET lookup
    // -------------------------------------------------------------------------

    // Returns the MET value for the named exercise.
    //
    // Named exercises: read from Application.Properties (MET × 10 integer) so
    // the user can tune values in Garmin Connect Mobile without reinstalling.
    //
    // Generic exercises: the MET is encoded directly in the name as an integer
    // suffix (e.g. "Generic MET 80" → MET 8.0).  This encoding lets us support
    // arbitrary MET values from the sub-menu without adding new properties.
    private function _getMet(name as String) as Float {
        // Generic encoding: "Generic MET NN" where NN is MET × 10.
        if (name.length() > 12 && name.substring(0, 12).equals("Generic MET ")) {
            var suffix = name.substring(12, name.length());
            if (suffix != null) {
                var raw = suffix.toNumber();
                if (raw != null && raw > 0) {
                    return raw.toFloat() / 10.0f;
                }
            }
        }

        // Named exercise: look up the property key and read from Connect IQ properties.
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
    // Generic exercises are handled in _getMet() directly; return null here.
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

    // Returns the stable integer ID written to the FIT exercise_id RECORD field.
    // IDs must not be renumbered once an activity has been recorded against this
    // schema, as they are the key used in post-processing to identify exercises.
    // Generic exercises all share ID 14; distinguish them by MET value in the
    // set_calories and set_duration fields rather than by exercise_id.
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
        // All "Generic MET NN" variants share ID 14.  The chosen MET is
        // recoverable from set_calories / set_duration in the FIT CSV.
        if (name.length() > 12 && name.substring(0, 12).equals("Generic MET ")) {
            return 14;
        }
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
