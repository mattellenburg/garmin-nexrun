import Toybox.Activity;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Segment state constants — used throughout the app via the global $ prefix.
enum {
    STATE_WARMUP    = 0,
    STATE_CARDIO    = 1,
    STATE_REST      = 2,
    STATE_STRENGTH  = 3,
    STATE_COOLDOWN  = 4,
    STATE_STRETCHING = 5,
}

// Root view for the NexRun activity screen.  Owns the 1-second UI timer,
// all FIT contributor fields, tracker instances, and the main draw loop.
// Delegates know about this class through its public surface only.
class NexRunView extends WatchUi.View {

    // -------------------------------------------------------------------------
    // Public state — read by delegates, trackers, and display modules
    // -------------------------------------------------------------------------

    public var _currentMode  = STATE_WARMUP;
    public var _currentPage  = 1;           // 1=Segment, 2=Totals, 3=Clock

    // Segment-transition summary overlay
    public var _showingSummary = false;
    public var _summaryTimer   = 0;         // Seconds until auto-dismiss

    // Lap origin markers — reset each time a new segment begins
    public var _lapStartTime     = 0;       // ms into activity timer
    public var _lapStartDistance = 0.0;     // metres

    // Data captured just before a segment switch (for the summary overlay)
    public var _lastMode     = 0;
    public var _lastLapTime  = 0;
    public var _lastLapDist  = 0.0;
    public var _lastLapPace  = "";
    public var _lastAvgHR    = 0;

    // -------------------------------------------------------------------------
    // FIT contributor fields
    // -------------------------------------------------------------------------
    // RECORD fields (IDs 0–2): written once per exercise stop then cleared on
    // the following tick via _pendingSnapClear.  IDs are stable — do not
    // renumber once activities have been recorded against this schema.
    //
    //   ID 0 — exercise_id      : integer ID of the exercise (see StrengthTracker)
    //   ID 1 — set_calories     : MET-based kcal for this exercise bout
    //   ID 2 — set_duration_sec : seconds the exercise timer ran
    //
    // SESSION / LAP fields (IDs 3–4): running calorie totals; do not count
    // against the Fenix 6 Pro's 16-field RECORD limit.
    //   ID 3 — strength_cals     (SESSION)
    //   ID 4 — lap_strength_cals (LAP)
    //
    // SESSION field (ID 5): total exercise bouts completed this activity.
    //   ID 5 — total_exercise_count (SESSION)
    //   ID 6 — lap_exercise_count   (LAP)

    public var _exerciseField    = null;    // RECORD ID 0
    public var _setCalField      = null;    // RECORD ID 1
    public var _setDurationField = null;    // RECORD ID 2

    public var _sessionStrengthCalsField = null;  // SESSION ID 3
    public var _lapStrengthCalsField     = null;  // LAP     ID 4
    public var _sessionExerciseCountField = null; // SESSION ID 5
    public var _lapExerciseCountField     = null; // LAP     ID 6

    // When true, onUpdate() zeros the three RECORD fields on the next tick so
    // the non-zero value written at exercise-stop has time to be flushed by the
    // FIT SDK before being cleared.  (Write-then-immediate-zero is a no-op.)
    public var _pendingSnapClear = false;

    // -------------------------------------------------------------------------
    // Tracker instances — one per segment type, created once at launch
    // -------------------------------------------------------------------------

    public var _warmUpTracker    as WarmUpTracker;
    public var _cardioTracker    as CardioTracker;
    public var _restTracker      as RestTracker;
    public var _strengthTracker  as StrengthTracker;
    public var _coolDownTracker  as CoolDownTracker;
    public var _stretchingTracker as StretchingTracker;

    // -------------------------------------------------------------------------
    // Private accumulated stats
    // -------------------------------------------------------------------------

    private var _timer;                         // 1-second UI refresh timer
    private var _maxHR            = 0;
    private var _totalXTSeconds   = 0;          // Cross-training (Strength) seconds
    private var _strengthStartMs  = 0;          // Timer ms when Strength mode began
    // Read by CardioTracker to compute the overall average pace display.
    public var _runTimeSec        = 0;          // Seconds spent moving in Cardio
    public var _runDistanceM      = 0.0;        // Metres accumulated in Cardio
    private var _paceWarningCount = 0;
    private var _lapStrengthCalories  = 0.0f;

    // Readable by StrengthTracker so it can write the SESSION calorie field.
    public var _totalStrengthCalories = 0.0f;
    // Running count of all exercise bouts across the session.
    public var _totalExerciseCount    = 0;
    private var _lapExerciseCount     = 0;

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    function initialize() {
        View.initialize();
        _warmUpTracker    = new WarmUpTracker(self);
        _cardioTracker    = new CardioTracker(self);
        _restTracker      = new RestTracker(self);
        _strengthTracker  = new StrengthTracker(self);
        _coolDownTracker  = new CoolDownTracker(self);
        _stretchingTracker = new StretchingTracker(self);
    }

    // -------------------------------------------------------------------------
    // Page navigation
    // -------------------------------------------------------------------------

    public function nextPage() as Void {
        _currentPage = _currentPage >= 3 ? 1 : _currentPage + 1;
        WatchUi.requestUpdate();
    }

    public function previousPage() as Void {
        _currentPage = _currentPage <= 1 ? 3 : _currentPage - 1;
        WatchUi.requestUpdate();
    }

    // -------------------------------------------------------------------------
    // FIT field registration
    // -------------------------------------------------------------------------

    // Creates all custom FIT contributor fields for the session.
    // Called once from NexRunDelegate after the session object is created.
    // Null-checked throughout so re-entry is safe.
    public function setupFitFields(session) as Void {
        if (session == null) { return; }

        // --- RECORD fields: written once per exercise bout then zeroed ---
        if (_exerciseField == null) {
            _exerciseField = session.createField(
                "exercise_id", 0, FitContributor.DATA_TYPE_SINT8,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
        }
        if (_setCalField == null) {
            _setCalField = session.createField(
                "set_calories", 1, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "kcal" });
        }
        if (_setDurationField == null) {
            _setDurationField = session.createField(
                "set_duration_sec", 2, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s" });
        }

        // --- SESSION / LAP fields: cumulative calorie totals ---
        if (_sessionStrengthCalsField == null) {
            _sessionStrengthCalsField = session.createField(
                "strength_cals", 3, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION,
                  :units => "kcal", :label => "Strength Calories" });
        }
        if (_lapStrengthCalsField == null) {
            _lapStrengthCalsField = session.createField(
                "lap_strength_cals", 4, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_LAP,
                  :units => "kcal", :label => "Lap Strength Calories" });
        }

        // --- SESSION / LAP fields: exercise bout counters ---
        if (_sessionExerciseCountField == null) {
            _sessionExerciseCountField = session.createField(
                "total_exercises", 5, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION,
                  :units => "bouts", :label => "Total Exercise Bouts" });
        }
        if (_lapExerciseCountField == null) {
            _lapExerciseCountField = session.createField(
                "lap_exercises", 6, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_LAP,
                  :units => "bouts", :label => "Lap Exercise Bouts" });
        }
    }

    // -------------------------------------------------------------------------
    // Mode switching
    // -------------------------------------------------------------------------

    // Transitions to newMode, performing all necessary cleanup on the departing
    // mode and setup for the arriving mode.  This is the single point of control
    // for tracker lifecycle so no delegate calls tracker methods directly.
    function setMode(newMode) as Void {
        var info = Activity.getActivityInfo();

        // ── Leaving Strength ────────────────────────────────────────────────
        if (_currentMode == $.STATE_STRENGTH && newMode != $.STATE_STRENGTH) {
            // Bank cross-training time before mode changes.
            if (info != null && info.timerTime != null && _strengthStartMs > 0) {
                _totalXTSeconds += (info.timerTime - _strengthStartMs) / 1000;
            }
            // Stop any running exercise and reset display state for next entry.
            _strengthTracker.stopExercise();
            _strengthTracker.resetDisplayState();
            // Zero the RECORD fields so stale values don't bleed into the next
            // segment's FIT rows.  The FIT SDK carries the last-written value
            // forward until overwritten, so an explicit zero is required.
            _zeroRecordFitFields();
        }

        // ── Entering Strength ────────────────────────────────────────────────
        if (newMode == $.STATE_STRENGTH) {
            _strengthStartMs =
                info != null && info.timerTime != null ? info.timerTime : 0;
        }

        _currentMode  = newMode;
        _lapStartTime =
            info != null && info.timerTime != null ? info.timerTime : 0;

        WatchUi.requestUpdate();
    }

    // Zeros all three RECORD-type FIT fields.  Called when leaving Strength
    // mode and on the tick after an exercise-stop write (_pendingSnapClear).
    private function _zeroRecordFitFields() as Void {
        if (_exerciseField    != null) { _exerciseField.setData(0); }
        if (_setCalField      != null) { _setCalField.setData(0.0f); }
        if (_setDurationField != null) { _setDurationField.setData(0.0f); }
    }

    // -------------------------------------------------------------------------
    // View lifecycle
    // -------------------------------------------------------------------------

    function onLayout(dc as Graphics.Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    function onShow() as Void {
        // Trigger onUpdate once per second to keep the display current.
        _timer = new Timer.Timer();
        _timer.start(method(:requestUpdate), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function requestUpdate() as Void {
        WatchUi.requestUpdate();
    }

    // -------------------------------------------------------------------------
    // Main draw loop
    // -------------------------------------------------------------------------

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Clear to black each frame.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- Deferred FIT field clear (write-then-zero pattern) ---
        // The FIT SDK flushes RECORD messages at 1 Hz.  Writing a value and
        // zeroing it in the same tick is a no-op, so we set _pendingSnapClear
        // at write time and clear the fields one tick later here.
        if (_pendingSnapClear) {
            _zeroRecordFitFields();
            _pendingSnapClear = false;
        }

        // --- Summary overlay countdown ---
        if (_showingSummary && _summaryTimer > 0) {
            _summaryTimer--;
        } else if (_summaryTimer <= 0) {
            _showingSummary = false;
        }

        // --- Gather activity info ---
        var info        = Activity.getActivityInfo();
        var totalTimeMs = info != null && info.timerTime != null        ? info.timerTime        : 0;
        var currentDistM = info != null && info.elapsedDistance != null ? info.elapsedDistance  : 0.0;
        var hr          = info != null && info.currentHeartRate != null ? info.currentHeartRate : 0;
        var calories    = info != null && info.calories != null         ? info.calories         : 0;

        // --- Background stat accumulation (runs every second while recording) ---
        if (info != null && info.timerState == Activity.TIMER_STATE_ON) {

            // Track max HR for the totals screen.
            if (info.currentHeartRate != null && info.currentHeartRate > _maxHR) {
                _maxHR = info.currentHeartRate;
            }

            // Accumulate Cardio-only speed for the overall pace calculation.
            // Only counts seconds where the user is actually moving (>0.2 m/s).
            if (_currentMode == STATE_CARDIO &&
                info.currentSpeed != null && info.currentSpeed > 0.2) {
                _runTimeSec++;
                _runDistanceM += info.currentSpeed;
            }

            // Delegate the per-second overlay countdown to StrengthTracker.
            if (_currentMode == STATE_STRENGTH) {
                _strengthTracker.tick();
            }
        }

        // --- Slow-pace haptic warning in Cardio (< ~2 mph) ---
        if (_currentMode == STATE_CARDIO && info != null &&
            info.timerState == Activity.TIMER_STATE_ON) {
            if (info.currentSpeed != null && info.currentSpeed < 0.89) {
                _paceWarningCount++;
                if (_paceWarningCount >= 5) {
                    if (Attention has :vibrate) {
                        Attention.vibrate([new Attention.VibeProfile(50, 500)]);
                    }
                    _paceWarningCount = 0;
                }
            } else {
                _paceWarningCount = 0;
            }
        }

        var lapTimeSec = (totalTimeMs - _lapStartTime) / 1000;
        var lapDistM   = currentDistM - _lapStartDistance;

        // --- Route to the correct data page ---
        if (_currentPage == 1) {
            var displayData = _getActiveTracker().getDisplayData(info, lapDistM);
            LapDisplay.draw(dc, w, h, lapTimeSec, hr, displayData);

        } else if (_currentPage == 2) {
            var totalDistMiles  = currentDistM * 0.000621371;
            var cardioOnlySpeed = _runTimeSec > 0 ? _runDistanceM / _runTimeSec : 0.0;
            // Include time already spent in Strength plus any ongoing Strength segment.
            var currentXTMs = (_currentMode == STATE_STRENGTH &&
                               info != null && info.timerTime != null)
                              ? info.timerTime - _strengthStartMs : 0;
            TotalDisplay.draw(dc, w, h, hr, {
                :totalDistMiles  => totalDistMiles,
                :totalTimeMs     => totalTimeMs,
                :calories        => calories,
                :cardioOnlySpeed => cardioOnlySpeed,
                :totalXTSeconds  => _totalXTSeconds + currentXTMs / 1000,
                :maxHR           => _maxHR,
            });

        } else if (_currentPage == 3) {
            TimeDisplay.draw(dc, w, h);
        }

        // --- Persistent overlays (drawn on top of every page) ---
        CommonDisplay.drawModeArc(dc, w, h, _currentMode);

        // Exercise-complete overlay takes priority over the segment-switch
        // summary so the user always gets immediate post-exercise feedback.
        if (_currentMode == STATE_STRENGTH && _strengthTracker._showingSetOverlay) {
            _drawExerciseOverlay(dc, w, h);
        } else if (_showingSummary) {
            CommonDisplay.drawSummaryOverlay(
                dc, w, h, _currentMode,
                _lastLapTime, _lastAvgHR, _lastMode,
                _lastLapPace, _lastLapDist);
        }
    }

    // -------------------------------------------------------------------------
    // Exercise-complete overlay
    // -------------------------------------------------------------------------

    // Full-screen overlay displayed for stSetOverlaySeconds after each exercise
    // bout ends.  Shows the exercise name, calories earned, and total set count.
    private function _drawExerciseOverlay(dc, w, h) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var name = _strengthTracker._lastExerciseType;
        if (name == null || name.equals("")) { name = "Exercise"; }

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.15, Graphics.FONT_MEDIUM,
            "DONE", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.38, Graphics.FONT_SMALL,
            name, Graphics.TEXT_JUSTIFY_CENTER);

        // Show the calories for this segment so far.
        var calStr = _strengthTracker.getSegmentCalories().format("%.1f") + " kcal";
        dc.drawText(w / 2, h * 0.58, Graphics.FONT_XTINY,
            calStr, Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h * 0.74, Graphics.FONT_XTINY,
            "Sets: " + _totalExerciseCount.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Keep the mode arc visible so the user retains segment context.
        CommonDisplay.drawModeArc(dc, w, h, _currentMode);
    }

    // -------------------------------------------------------------------------
    // Tracker dispatch
    // -------------------------------------------------------------------------

    // Returns the tracker for the active segment.  Adding a new segment type
    // requires only a new branch here (and a new tracker class).
    private function _getActiveTracker() {
        if (_currentMode == STATE_CARDIO)     { return _cardioTracker; }
        if (_currentMode == STATE_REST)       { return _restTracker; }
        if (_currentMode == STATE_STRENGTH)   { return _strengthTracker; }
        if (_currentMode == STATE_COOLDOWN)   { return _coolDownTracker; }
        if (_currentMode == STATE_STRETCHING) { return _stretchingTracker; }
        return _warmUpTracker;
    }

    // -------------------------------------------------------------------------
    // Shared helpers called by trackers
    // -------------------------------------------------------------------------

    // Formats a pace + distance display dictionary for running-type segments.
    // Shared by WarmUpTracker, CardioTracker, and CoolDownTracker.
    public function getRunningUnits(info, lapDistM as Float) as Dictionary {
        if (info == null) {
            return { :valueL => "--:--", :labelL => "MIN/MILE",
                     :valueR => "0.00",  :labelR => "MILES" };
        }
        var settings = System.getDeviceSettings();
        var isMetric = settings.distanceUnits == System.UNIT_METRIC;
        var res = {};

        if (isMetric) {
            res[:valueR] = (lapDistM / 1000.0).format("%.2f");
            res[:labelR] = "KM";
            res[:labelL] = "MIN/KM";
            res[:valueL] = (info.currentSpeed != null && info.currentSpeed > 0.2)
                ? CommonDisplay.formatTime((1000.0 / info.currentSpeed).toNumber())
                : "--:--";
        } else {
            res[:valueR] = (lapDistM * 0.000621371).format("%.2f");
            res[:labelR] = "MILES";
            res[:labelL] = "MIN/MILE";
            var speed = (info.currentSpeed != null) ? info.currentSpeed
                      : (info.averageSpeed != null)  ? info.averageSpeed : 0.0;
            res[:valueL] = speed > 0.05
                ? CommonDisplay.formatTime((1609.34 / speed).toNumber())
                : "--:--";
        }
        return res;
    }

    // Resets lap-scoped in-memory accumulators and their FIT LAP fields.
    // Called by NexRunMenuDelegate after addLap() so each new lap starts clean.
    // StrengthTracker's own lap state is reset separately via resetLap().
    public function resetLapStats() as Void {
        _lapStrengthCalories = 0.0f;
        _lapExerciseCount    = 0;
        if (_lapStrengthCalsField  != null) { _lapStrengthCalsField.setData(0.0f); }
        if (_lapExerciseCountField != null) { _lapExerciseCountField.setData(0); }
    }

    // Accumulates per-exercise calories into session and lap totals and writes
    // them to the corresponding SESSION and LAP FIT fields.
    // Also increments the exercise bout counter fields.
    // Called by StrengthTracker._writeSetResults() after each exercise stops.
    public function updateTotalCalories(kcal as Float) as Void {
        _totalStrengthCalories += kcal;
        _lapStrengthCalories   += kcal;
        _totalExerciseCount++;
        _lapExerciseCount++;

        if (_sessionStrengthCalsField  != null) {
            _sessionStrengthCalsField.setData(_totalStrengthCalories);
        }
        if (_lapStrengthCalsField != null) {
            _lapStrengthCalsField.setData(_lapStrengthCalories);
        }
        if (_sessionExerciseCountField != null) {
            _sessionExerciseCountField.setData(_totalExerciseCount);
        }
        if (_lapExerciseCountField != null) {
            _lapExerciseCountField.setData(_lapExerciseCount);
        }

        WatchUi.requestUpdate();
    }
}
