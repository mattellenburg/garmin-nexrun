import Toybox.Activity;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Segment state constants — used throughout the app via the global $ prefix.
enum {
    STATE_WARMUP     = 0,
    STATE_CARDIO     = 1,
    STATE_REST       = 2,
    STATE_STRENGTH   = 3,
    STATE_COOLDOWN   = 4,
    STATE_STRETCHING = 5,
}

// Root view for the NexRun activity screen.  Owns the 1-second UI timer,
// all FIT contributor fields, tracker instances, and the main draw loop.
class NexRunView extends WatchUi.View {

    // Public state — read by delegates, trackers, and display modules.
    public var _currentMode = STATE_WARMUP;
    public var _currentPage = 1;           // 1=Segment, 2=Totals, 3=Clock

    // Segment-switch overlay: shows current segment name for 3 seconds.
    public var _showingSummary = false;
    public var _summaryTimer   = 0;

    // Lap origin markers — reset each time the user switches segments.
    // _lapStartTime tracks the activity timer (info.timerTime) and is used
    // for distance-based lap math.  It freezes whenever the session is
    // paused (Strength/Rest segments — see NexRunMenuDelegate), which is
    // fine for distance since those segments are stationary.
    public var _lapStartTime     = 0;       // ms into activity timer
    public var _lapStartDistance = 0.0;     // metres

    // Device-uptime equivalent of _lapStartTime, used ONLY for the on-screen
    // lap clock.  System.getTimer() keeps advancing even while the session
    // is paused, so the displayed lap timer continues to count up correctly
    // during Rest and Strength segments instead of freezing at 0:00.
    private var _lapStartUptimeMs = 0;

    // True once the user has actually pressed Start (set by resetLapTimer(),
    // called from NexRunDelegate._startActivity()).  Gates the on-screen lap
    // clock so it stays at 0:00 on the pre-start watch face instead of
    // ticking up on its own — the 1Hz UI timer runs as soon as the view is
    // shown, independent of whether recording has begun.
    private var _activityStarted = false;

    // Monotonically increasing counter, incremented in setMode() on every switch.
    // Written to every RECORD row so post-processing can group by segment.
    public var _segmentNumber = 0;

    // FIT RECORD fields — schema (IDs stable; never renumber after recording):
    //   Per-exercise (written at stop, zeroed next tick via _pendingSnapClear):
    //     0 exercise_id      SINT8   — stable integer ID for exercise type
    //     1 set_calories     FLOAT   — MET-based kcal for this bout
    //     2 set_duration_sec FLOAT   — seconds the exercise timer ran
    //   Per-row (written every second for all segments):
    //     7 accel_x          SINT16  — milli-g; non-zero only during Strength
    //     8 accel_y          SINT16  — milli-g; non-zero only during Strength
    //     9 accel_z          SINT16  — milli-g; non-zero only during Strength
    //    10 segment_number   UINT16  — current segment index
    //    11 session_calories  UINT16  — device calorie total at this moment
    //   SESSION/LAP (do not count toward the 16-field RECORD limit):
    //     3 strength_cals    FLOAT SESSION  — cumulative MET calories
    //     4 lap_strength_cals FLOAT LAP
    //     5 total_exercises  UINT16 SESSION — exercise bout count
    //     6 lap_exercises    UINT16 LAP
    // Total RECORD fields: 8 — well under Fenix 6 Pro's 16-field limit.

    public var _exerciseField    = null;  // RECORD  0
    public var _setCalField      = null;  // RECORD  1
    public var _setDurationField = null;  // RECORD  2
    public var _sessionStrengthCalsField  = null;  // SESSION 3
    public var _lapStrengthCalsField      = null;  // LAP     4
    public var _sessionExerciseCountField = null;  // SESSION 5
    public var _lapExerciseCountField     = null;  // LAP     6
    public var _accelXField          = null;  // RECORD  7
    public var _accelYField          = null;  // RECORD  8
    public var _accelZField          = null;  // RECORD  9
    public var _segmentNumberField   = null;  // RECORD 10
    public var _sessionCaloriesField = null;  // RECORD 11

    // When true, zero the three exercise RECORD fields on the next tick so the
    // non-zero value written at exercise-stop has time to be flushed first.
    public var _pendingSnapClear = false;

    // Tracker instances — one per segment type, created once at launch.
    public var _warmUpTracker    as WarmUpTracker;
    public var _cardioTracker    as CardioTracker;
    public var _restTracker      as RestTracker;
    public var _strengthTracker  as StrengthTracker;
    public var _coolDownTracker  as CoolDownTracker;
    public var _stretchingTracker as StretchingTracker;

    // Private accumulated stats.
    private var _timer;
    private var _maxHR           = 0;
    private var _totalXTSeconds  = 0;      // Cross-training (Strength) seconds
    private var _strengthStartMs = 0;      // Timer ms when Strength mode began
    public  var _runTimeSec      = 0;      // Seconds moving in Cardio (for avg pace)
    public  var _runDistanceM    = 0.0;    // Metres accumulated in Cardio
    private var _paceWarningCount    = 0;
    private var _lapStrengthCalories = 0.0f;
    public  var _totalStrengthCalories = 0.0f;
    public  var _totalExerciseCount    = 0;
    private var _lapExerciseCount      = 0;

    function initialize() {
        View.initialize();
        _warmUpTracker    = new WarmUpTracker(self);
        _cardioTracker    = new CardioTracker(self);
        _restTracker      = new RestTracker(self);
        _strengthTracker  = new StrengthTracker(self);
        _coolDownTracker  = new CoolDownTracker(self);
        _stretchingTracker = new StretchingTracker(self);
        // Without this, the lap clock would show raw device/simulator uptime
        // (e.g. "273:00:00") on the pre-start screen, since onUpdate() begins
        // running via the 1Hz timer in onShow() — well before the user presses
        // Start and resetLapTimer() is called again to mark the real origin.
        _lapStartUptimeMs = System.getTimer();
    }

    // ---- Page navigation ----

    public function nextPage() as Void {
        _currentPage = _currentPage >= 3 ? 1 : _currentPage + 1;
        WatchUi.requestUpdate();
    }

    public function previousPage() as Void {
        _currentPage = _currentPage <= 1 ? 3 : _currentPage - 1;
        WatchUi.requestUpdate();
    }

    // ---- FIT field registration ----

    // Creates all custom FIT contributor fields.  Called once from NexRunDelegate
    // after the session is created.  Null-checked so re-entry is safe.
    public function setupFitFields(session) as Void {
        if (session == null) { return; }
        var R = FitContributor.MESG_TYPE_RECORD;
        var S = FitContributor.MESG_TYPE_SESSION;
        var L = FitContributor.MESG_TYPE_LAP;
        var i8  = FitContributor.DATA_TYPE_SINT8;
        var f32 = FitContributor.DATA_TYPE_FLOAT;
        var u16 = FitContributor.DATA_TYPE_UINT16;
        var s16 = FitContributor.DATA_TYPE_SINT16;

        if (_exerciseField    == null) { _exerciseField    = session.createField("exercise_id",       0, i8,  { :mesgType => R }); }
        if (_setCalField      == null) { _setCalField      = session.createField("set_calories",      1, f32, { :mesgType => R, :units => "kcal" }); }
        if (_setDurationField == null) { _setDurationField = session.createField("set_duration_sec",  2, f32, { :mesgType => R, :units => "s" }); }

        if (_sessionStrengthCalsField  == null) { _sessionStrengthCalsField  = session.createField("strength_cals",      3, f32, { :mesgType => S, :units => "kcal",  :label => "Strength Calories" }); }
        if (_lapStrengthCalsField      == null) { _lapStrengthCalsField      = session.createField("lap_strength_cals",  4, f32, { :mesgType => L, :units => "kcal",  :label => "Lap Strength Calories" }); }
        if (_sessionExerciseCountField == null) { _sessionExerciseCountField = session.createField("total_exercises",    5, u16, { :mesgType => S, :units => "bouts", :label => "Total Exercise Bouts" }); }
        if (_lapExerciseCountField     == null) { _lapExerciseCountField     = session.createField("lap_exercises",      6, u16, { :mesgType => L, :units => "bouts", :label => "Lap Exercise Bouts" }); }

        if (_accelXField          == null) { _accelXField          = session.createField("accel_x",          7,  s16, { :mesgType => R, :units => "mG" }); }
        if (_accelYField          == null) { _accelYField          = session.createField("accel_y",          8,  s16, { :mesgType => R, :units => "mG" }); }
        if (_accelZField          == null) { _accelZField          = session.createField("accel_z",          9,  s16, { :mesgType => R, :units => "mG" }); }
        if (_segmentNumberField   == null) { _segmentNumberField   = session.createField("segment_number",   10, u16, { :mesgType => R }); }
        if (_sessionCaloriesField == null) { _sessionCaloriesField = session.createField("session_calories", 11, u16, { :mesgType => R, :units => "kcal" }); }
    }

    // ---- Mode switching ----

    // Transitions to newMode.  Single point of control for tracker lifecycle.
    function setMode(newMode) as Void {
        var info = Activity.getActivityInfo();

        if (_currentMode == $.STATE_STRENGTH && newMode != $.STATE_STRENGTH) {
            // Bank cross-training time, then close any open exercise set.
            if (info != null && info.timerTime != null && _strengthStartMs > 0) {
                _totalXTSeconds += (info.timerTime - _strengthStartMs) / 1000;
            }
            _strengthTracker.stopExercise();
            _strengthTracker.resetDisplayState();
            // Zero exercise RECORD fields so stale values don't bleed into the
            // next segment — the FIT SDK carries the last written value forward.
            _zeroExerciseFitFields();
        }

        if (newMode == $.STATE_STRENGTH) {
            _strengthStartMs = info != null && info.timerTime != null ? info.timerTime : 0;
        }

        // Increment so every FIT row carries the current segment index.
        _segmentNumber++;
        _currentMode  = newMode;
        _lapStartTime = info != null && info.timerTime != null ? info.timerTime : 0;
        // Always advances, even when the session is paused — see field comment.
        _lapStartUptimeMs = System.getTimer();
        WatchUi.requestUpdate();
    }

    // Resets the uptime-based lap clock origin.  Called once by
    // NexRunDelegate._startActivity() right after session.start() succeeds.
    // System.getTimer() is relative to device/app uptime, not activity start,
    // so without this the very first WARMUP segment's lap clock would show a
    // large stale value instead of starting from 0:00.
    //
    // Also flips _activityStarted to true.  Before this is called, the lap
    // clock displayed in onUpdate() stays pinned at 0:00 instead of ticking
    // up — the 1Hz UI timer in onShow() runs (and redraws the rest of the
    // watch face) well before the user presses Start, and without this guard
    // the lap clock would visibly count up on its own before recording begins.
    public function resetLapTimer() as Void {
        _lapStartUptimeMs = System.getTimer();
        _activityStarted  = true;
    }

    // Zeros the three exercise RECORD fields (IDs 0–2).
    private function _zeroExerciseFitFields() as Void {
        if (_exerciseField    != null) { _exerciseField.setData(0); }
        if (_setCalField      != null) { _setCalField.setData(0.0f); }
        if (_setDurationField != null) { _setDurationField.setData(0.0f); }
    }

    // ---- View lifecycle ----

    function onLayout(dc as Graphics.Dc) as Void { setLayout(Rez.Layouts.MainLayout(dc)); }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:requestUpdate), 1000, true);
    }

    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    function requestUpdate() as Void { WatchUi.requestUpdate(); }

    // ---- Main draw loop ----

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Deferred FIT field clear: the FIT SDK flushes RECORD at 1 Hz, so
        // writing and zeroing in the same tick is a no-op.  We set
        // _pendingSnapClear at write time and zero one tick later here.
        if (_pendingSnapClear) {
            _zeroExerciseFitFields();
            _pendingSnapClear = false;
        }

        // Summary overlay countdown.
        if (_showingSummary && _summaryTimer > 0) {
            _summaryTimer--;
        } else if (_summaryTimer <= 0) {
            _showingSummary = false;
        }

        var info         = Activity.getActivityInfo();
        var totalTimeMs  = info != null && info.timerTime != null        ? info.timerTime        : 0;
        var currentDistM = info != null && info.elapsedDistance != null  ? info.elapsedDistance  : 0.0;
        var hr           = info != null && info.currentHeartRate != null ? info.currentHeartRate : 0;
        var calories     = info != null && info.calories != null         ? info.calories         : 0;

        if (info != null && info.timerState == Activity.TIMER_STATE_ON) {
            if (info.currentHeartRate != null && info.currentHeartRate > _maxHR) {
                _maxHR = info.currentHeartRate;
            }
            // Accumulate Cardio-only speed for overall average pace display.
            // Only counts seconds where the user is actually moving (>0.2 m/s).
            if (_currentMode == STATE_CARDIO &&
                info.currentSpeed != null && info.currentSpeed > 0.2) {
                _runTimeSec++;
                _runDistanceM += info.currentSpeed;
            }
            if (_currentMode == STATE_STRENGTH) {
                _strengthTracker.tick();
            }
        }

        // Slow-pace haptic warning in Cardio (< ~2 mph).
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

        // Write per-row FIT fields (accel, segment number, calorie total).
        _writePerRowFitFields(calories);

        // The on-screen lap clock uses device uptime (System.getTimer()), not
        // the activity timer.  The activity timer is intentionally paused
        // during Strength/Rest segments (see NexRunMenuDelegate) so Garmin
        // Connect's avg pace excludes that time — but that same pause would
        // freeze this display at 0:00 if we used info.timerTime here instead.
        // Gated on _activityStarted so the clock stays at 0:00 on the
        // pre-start watch face rather than counting up before Start is pressed.
        var lapTimeSec = _activityStarted
                         ? (System.getTimer() - _lapStartUptimeMs) / 1000 : 0;
        var lapDistM   = currentDistM - _lapStartDistance;

        if (_currentPage == 1) {
            var displayData = _getActiveTracker().getDisplayData(info, lapDistM);
            LapDisplay.draw(dc, w, h, lapTimeSec, hr, displayData);
        } else if (_currentPage == 2) {
            var totalDistMiles  = currentDistM * 0.000621371;
            var cardioOnlySpeed = _runTimeSec > 0 ? _runDistanceM / _runTimeSec : 0.0;
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

        CommonDisplay.drawModeArc(dc, w, h, _currentMode);

        if (_currentMode == STATE_STRENGTH && _strengthTracker._showingSetOverlay) {
            _drawExerciseOverlay(dc, w, h);
        } else if (_showingSummary) {
            _drawSegmentSummary(dc, w, h);
        }
    }

    // ---- Per-row FIT field writes ----

    // Writes fields that appear in every RECORD row: accelerometer axes
    // (non-zero only in Strength), segment number, and device calorie total.
    private function _writePerRowFitFields(calories as Number) as Void {
        // Read accelerometer synchronously on the UI thread — safe because we
        // never call this from a sensor callback.  Zero for non-Strength segments
        // so CSV columns are consistently populated throughout the activity.
        var ax = 0; var ay = 0; var az = 0;
        if (_currentMode == STATE_STRENGTH) {
            var si = Sensor.getInfo();
            if (si != null && si.accel != null) {
                var a = si.accel;
                ax = a[0] != null ? a[0] : 0;
                ay = a[1] != null ? a[1] : 0;
                az = a[2] != null ? a[2] : 0;
            }
        }
        if (_accelXField != null) { _accelXField.setData(ax); }
        if (_accelYField != null) { _accelYField.setData(ay); }
        if (_accelZField != null) { _accelZField.setData(az); }
        if (_segmentNumberField   != null) { _segmentNumberField.setData(_segmentNumber); }
        if (_sessionCaloriesField != null) { _sessionCaloriesField.setData(calories); }
    }

    // ---- Overlays ----

    // Minimal 3-second overlay after each segment switch.  Shows only the
    // current segment name in its mode colour so the transition is unambiguous.
    private function _drawSegmentSummary(dc, w, h) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var names  = ["WARMUP", "CARDIO", "REST", "STRENGTH", "COOL DOWN", "STRETCHING"];
        var colors = [Graphics.COLOR_GREEN, Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW,
                      Graphics.COLOR_RED,   Graphics.COLOR_BLUE,   Graphics.COLOR_PURPLE];
        var color = (_currentMode >= 0 && _currentMode < colors.size())
                    ? colors[_currentMode] : Graphics.COLOR_WHITE;
        var name  = (_currentMode >= 0 && _currentMode < names.size())
                    ? names[_currentMode]  : "SEGMENT";
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 20, Graphics.FONT_LARGE,
            name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        CommonDisplay.drawModeArc(dc, w, h, _currentMode);
    }

    // Post-exercise overlay: shows exercise name, calories, and total set count.
    private function _drawExerciseOverlay(dc, w, h) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var name = _strengthTracker._lastExerciseType;
        if (name == null || name.equals("")) { name = "Exercise"; }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.15, Graphics.FONT_MEDIUM, "DONE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.38, Graphics.FONT_SMALL, name, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.58, Graphics.FONT_XTINY,
            _strengthTracker.getSegmentCalories().format("%.1f") + " kcal",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.74, Graphics.FONT_XTINY,
            "Sets: " + _totalExerciseCount.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        CommonDisplay.drawModeArc(dc, w, h, _currentMode);
    }

    // ---- Tracker dispatch ----

    private function _getActiveTracker() {
        if (_currentMode == STATE_CARDIO)     { return _cardioTracker; }
        if (_currentMode == STATE_REST)       { return _restTracker; }
        if (_currentMode == STATE_STRENGTH)   { return _strengthTracker; }
        if (_currentMode == STATE_COOLDOWN)   { return _coolDownTracker; }
        if (_currentMode == STATE_STRETCHING) { return _stretchingTracker; }
        return _warmUpTracker;
    }

    // ---- Shared helpers called by trackers ----

    // Formats a pace + distance display dictionary for running-type segments.
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
                ? CommonDisplay.formatTime((1000.0 / info.currentSpeed).toNumber()) : "--:--";
        } else {
            res[:valueR] = (lapDistM * 0.000621371).format("%.2f");
            res[:labelR] = "MILES";
            res[:labelL] = "MIN/MILE";
            var speed = (info.currentSpeed != null) ? info.currentSpeed
                      : (info.averageSpeed  != null) ? info.averageSpeed : 0.0;
            res[:valueL] = speed > 0.05
                ? CommonDisplay.formatTime((1609.34 / speed).toNumber()) : "--:--";
        }
        return res;
    }

    // Resets lap-scoped accumulators and FIT LAP fields.
    // Called by NexRunMenuDelegate after addLap().
    public function resetLapStats() as Void {
        _lapStrengthCalories = 0.0f;
        _lapExerciseCount    = 0;
        if (_lapStrengthCalsField  != null) { _lapStrengthCalsField.setData(0.0f); }
        if (_lapExerciseCountField != null) { _lapExerciseCountField.setData(0); }
    }

    // Accumulates per-exercise calories and increments exercise-bout counters.
    // Called by StrengthTracker after each exercise stops.
    public function updateTotalCalories(kcal as Float) as Void {
        _totalStrengthCalories += kcal;
        _lapStrengthCalories   += kcal;
        _totalExerciseCount++;
        _lapExerciseCount++;
        if (_sessionStrengthCalsField  != null) { _sessionStrengthCalsField.setData(_totalStrengthCalories); }
        if (_lapStrengthCalsField      != null) { _lapStrengthCalsField.setData(_lapStrengthCalories); }
        if (_sessionExerciseCountField != null) { _sessionExerciseCountField.setData(_totalExerciseCount); }
        if (_lapExerciseCountField     != null) { _lapExerciseCountField.setData(_lapExerciseCount); }
        WatchUi.requestUpdate();
    }
}
