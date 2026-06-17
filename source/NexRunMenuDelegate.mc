import Toybox.Activity;
import Toybox.Lang;
import Toybox.WatchUi;

// Handles item selection from the segment-switcher menu (opened by the Back
// button while an activity is recording) and from the exercise sub-menu
// shown when the user taps "Exercise" inside a Strength segment.
//
// MENU HIERARCHY:
//   Segment menu  →  Warmup | Cardio | Rest | Strength | Cool Down | Stretching
//                            └─ (when already in Strength) Exercise ──►
//   Exercise menu →  Exit | Battle Ropes | Burpees | … | Tire Flips
//
// "Exit" in the exercise menu closes the menu without starting an exercise.
// All other exercise items call StrengthTracker.startExercise() and close
// both menus so the user is returned immediately to the watch face.
class NexRunMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view    as NexRunView;
    private var _session; // ActivityRecording.Session — nullable

    function initialize(view as NexRunView, session) {
        Menu2InputDelegate.initialize();
        _view    = view;
        _session = session;
    }

    // -------------------------------------------------------------------------
    // Segment menu selection
    // -------------------------------------------------------------------------

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        var v  = _view as NexRunView;

        // "exercise" is only present when the user is already in Strength mode.
        // Push the exercise sub-menu instead of switching segments.
        if (id.equals("exercise")) {
            _pushExerciseMenu();
            return;
        }

        // ── Capture current-segment stats before the switch ──────────────────
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            v._lastMode    = v._currentMode;
            v._lastLapTime = (info.timerTime - v._lapStartTime) / 1000;

            if (info.elapsedDistance != null) {
                var lapDistM  = info.elapsedDistance - v._lapStartDistance;
                v._lastLapDist = lapDistM / 1609.34;
                if (v._lastLapDist > 0.01 && v._lastLapTime > 0) {
                    var paceSecPerMile = (v._lastLapTime / v._lastLapDist).toNumber();
                    v._lastLapPace = Lang.format("$1$:$2$", [
                        paceSecPerMile / 60,
                        (paceSecPerMile % 60).format("%02d"),
                    ]);
                }
            }
        }

        // ── Write the FIT lap marker and reset lap-scoped fields ─────────────
        if (_session != null && _session.isRecording()) {
            _session.addLap();
            v._strengthTracker.resetLap();  // Reset StrengthTracker lap counters
            v.resetLapStats();               // Reset view lap accumulators + FIT LAP fields
        }

        // ── Show the transition summary overlay ───────────────────────────────
        v._showingSummary = true;
        v._summaryTimer   = 10;

        // ── Reset lap origin markers to "now" ─────────────────────────────────
        if (info != null && info.timerTime != null) {
            v._lapStartTime = info.timerTime;
            if (info.elapsedDistance != null) {
                v._lapStartDistance = info.elapsedDistance;
            }
        }

        // ── Switch to the chosen segment ──────────────────────────────────────
        if      (id.equals("warmup"))     { v.setMode($.STATE_WARMUP); }
        else if (id.equals("cardio"))     { v.setMode($.STATE_CARDIO); }
        else if (id.equals("rest"))       { v.setMode($.STATE_REST); }
        else if (id.equals("strength"))   { v.setMode($.STATE_STRENGTH); }
        else if (id.equals("cooldown"))   { v.setMode($.STATE_COOLDOWN); }
        else if (id.equals("stretching")) { v.setMode($.STATE_STRETCHING); }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }

    // -------------------------------------------------------------------------
    // Exercise sub-menu
    // -------------------------------------------------------------------------

    // Builds and pushes the exercise selection list.  "Exit" is always first
    // so the user can back out without accidentally starting an exercise.
    private function _pushExerciseMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Choose Exercise" });

        menu.addItem(new WatchUi.MenuItem("Exit",             null, "ex_exit",          null));
        menu.addItem(new WatchUi.MenuItem("Battle Ropes",     null, "ex_battleropes",   null));
        menu.addItem(new WatchUi.MenuItem("Burpees",          null, "ex_burpees",       null));
        menu.addItem(new WatchUi.MenuItem("Dips",             null, "ex_dips",          null));
        menu.addItem(new WatchUi.MenuItem("Kettlebell Swings",null, "ex_kettlebell",    null));
        menu.addItem(new WatchUi.MenuItem("Med Ball Throws",  null, "ex_medball",       null));
        menu.addItem(new WatchUi.MenuItem("Monkey Bars",      null, "ex_monkeybars",    null));
        menu.addItem(new WatchUi.MenuItem("Mountain Climbers",null, "ex_mtnclimbers",   null));
        menu.addItem(new WatchUi.MenuItem("Pull-ups",         null, "ex_pullups",       null));
        menu.addItem(new WatchUi.MenuItem("Push-ups",         null, "ex_pushups",       null));
        menu.addItem(new WatchUi.MenuItem("Rope Climb",       null, "ex_ropeclimb",     null));
        menu.addItem(new WatchUi.MenuItem("Sled Push/Pull",   null, "ex_sled",          null));
        menu.addItem(new WatchUi.MenuItem("Sledgehammer",     null, "ex_sledgehammer",  null));
        menu.addItem(new WatchUi.MenuItem("Tire Flips",       null, "ex_tireflips",     null));

        WatchUi.pushView(menu, new ExerciseMenuDelegate(_view), WatchUi.SLIDE_UP);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExerciseMenuDelegate
// Handles selection in the exercise sub-menu pushed by NexRunMenuDelegate.
// Kept in this file to stay under the 500-line cap while keeping related logic
// co-located.
// ─────────────────────────────────────────────────────────────────────────────
class ExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;

        if (id.equals("ex_exit")) {
            // Close only the exercise sub-menu; leave the segment menu open.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }

        // Map menu IDs to the display names used by StrengthTracker.
        var name = _nameForId(id);
        if (name != null) {
            (_view as NexRunView)._strengthTracker.startExercise(name);
        }

        // Close both the exercise sub-menu AND the segment menu so the user
        // returns directly to the watch face with the exercise timer running.
        WatchUi.popView(WatchUi.SLIDE_DOWN); // exercise sub-menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // segment menu
        WatchUi.requestUpdate();
    }

    // Converts a menu item ID string to the canonical exercise display name
    // used by StrengthTracker and written to FIT fields.
    private function _nameForId(id as String) as String? {
        if (id.equals("ex_battleropes"))   { return "Battle Ropes"; }
        if (id.equals("ex_burpees"))       { return "Burpees"; }
        if (id.equals("ex_dips"))          { return "Dips"; }
        if (id.equals("ex_kettlebell"))    { return "Kettlebell Swings"; }
        if (id.equals("ex_medball"))       { return "Med Ball Throws"; }
        if (id.equals("ex_monkeybars"))    { return "Monkey Bars"; }
        if (id.equals("ex_mtnclimbers"))   { return "Mountain Climbers"; }
        if (id.equals("ex_pullups"))       { return "Pull-ups"; }
        if (id.equals("ex_pushups"))       { return "Push-ups"; }
        if (id.equals("ex_ropeclimb"))     { return "Rope Climb"; }
        if (id.equals("ex_sled"))          { return "Sled Push/Pull"; }
        if (id.equals("ex_sledgehammer"))  { return "Sledgehammer"; }
        if (id.equals("ex_tireflips"))     { return "Tire Flips"; }
        return null;
    }
}
