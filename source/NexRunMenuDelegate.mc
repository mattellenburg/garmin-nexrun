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
//   Exercise menu →  Rest | Exit | Battle Ropes | … | Tire Flips | Generic ──►
//   Generic menu  →  MET 5.0 | MET 6.0 | … | MET 12.0
//
// "Rest" in the exercise menu starts an in-strength rest interval: the exercise
// timer runs but no calories are written when it ends, so the calorie total is
// not inflated by recovery time.
//
// "Exit" closes the exercise menu without starting anything.
//
// "Generic" pushes a third-level MET picker; the chosen MET value is encoded
// into the exercise name as "Generic MET NN" (NN = MET × 10) so StrengthTracker
// can recover the float MET without additional properties.xml entries.
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

    // Builds and pushes the exercise selection list.
    //
    // "Rest" is first so the user can quickly start an in-strength rest interval
    // without navigating away to the Rest segment.  It uses StrengthTracker's
    // timer but writes zero calories when stopped.
    //
    // "Exit" is second so the user can back out without accidentally starting
    // an exercise.
    //
    // "Generic" is last and pushes a MET-picker sub-menu on selection.
    private function _pushExerciseMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Choose Exercise" });

        menu.addItem(new WatchUi.MenuItem("Rest",              "No calories logged", "ex_rest",         null));
        menu.addItem(new WatchUi.MenuItem("Exit",              null,                 "ex_exit",          null));
        menu.addItem(new WatchUi.MenuItem("Battle Ropes",      null,                 "ex_battleropes",   null));
        menu.addItem(new WatchUi.MenuItem("Burpees",           null,                 "ex_burpees",       null));
        menu.addItem(new WatchUi.MenuItem("Dips",              null,                 "ex_dips",          null));
        menu.addItem(new WatchUi.MenuItem("Kettlebell Swings", null,                 "ex_kettlebell",    null));
        menu.addItem(new WatchUi.MenuItem("Med Ball Throws",   null,                 "ex_medball",       null));
        menu.addItem(new WatchUi.MenuItem("Monkey Bars",       null,                 "ex_monkeybars",    null));
        menu.addItem(new WatchUi.MenuItem("Mountain Climbers", null,                 "ex_mtnclimbers",   null));
        menu.addItem(new WatchUi.MenuItem("Pull-ups",          null,                 "ex_pullups",       null));
        menu.addItem(new WatchUi.MenuItem("Push-ups",          null,                 "ex_pushups",       null));
        menu.addItem(new WatchUi.MenuItem("Rope Climb",        null,                 "ex_ropeclimb",     null));
        menu.addItem(new WatchUi.MenuItem("Sled Push/Pull",    null,                 "ex_sled",          null));
        menu.addItem(new WatchUi.MenuItem("Sledgehammer",      null,                 "ex_sledgehammer",  null));
        menu.addItem(new WatchUi.MenuItem("Tire Flips",        null,                 "ex_tireflips",     null));
        menu.addItem(new WatchUi.MenuItem("Generic",           "Choose MET value",   "ex_generic",       null));

        WatchUi.pushView(menu, new ExerciseMenuDelegate(_view), WatchUi.SLIDE_UP);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExerciseMenuDelegate
// Handles selection in the exercise sub-menu pushed by NexRunMenuDelegate.
// "Generic" delegates further to GenericMetMenuDelegate rather than starting
// an exercise directly.
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

        if (id.equals("ex_generic")) {
            // Push the MET picker as a third level; don't close anything yet.
            // GenericMetMenuDelegate will close all three levels on selection.
            _pushGenericMetMenu();
            return;
        }

        // Named exercise or Rest: map ID to display name and start immediately.
        var name = _nameForId(id);
        if (name != null) {
            (_view as NexRunView)._strengthTracker.startExercise(name);
        }

        // Close both the exercise sub-menu AND the segment menu so the user
        // returns directly to the watch face with the timer running.
        WatchUi.popView(WatchUi.SLIDE_DOWN); // exercise sub-menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // segment menu
        WatchUi.requestUpdate();
    }

    // Pushes the three-level Generic MET picker.
    // The GenericMetMenuDelegate closes all three menus when a MET is chosen.
    private function _pushGenericMetMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Generic MET" });

        // MET values × 10 as item IDs span the range from light calisthenics
        // (MET 5.0) to very vigorous effort (MET 12.0).  The subtitle shows
        // the reference named exercise at the nearest MET so the user can
        // calibrate their choice without memorising MET numbers.
        menu.addItem(new WatchUi.MenuItem("MET 5.0", "Light effort",       "gmet_50",  null));
        menu.addItem(new WatchUi.MenuItem("MET 6.0", "Moderate effort",    "gmet_60",  null));
        menu.addItem(new WatchUi.MenuItem("MET 7.0", "Moderate-vigorous",  "gmet_70",  null));
        menu.addItem(new WatchUi.MenuItem("MET 8.0", "~ Burpees / Dips",   "gmet_80",  null));
        menu.addItem(new WatchUi.MenuItem("MET 9.0", "~ Kettlebell / Sled","gmet_90",  null));
        menu.addItem(new WatchUi.MenuItem("MET 10.0","~ Battle Ropes",     "gmet_100", null));
        menu.addItem(new WatchUi.MenuItem("MET 11.0","~ Pull-ups",         "gmet_110", null));
        menu.addItem(new WatchUi.MenuItem("MET 12.0","~ Rope Climb",       "gmet_120", null));

        WatchUi.pushView(menu, new GenericMetMenuDelegate(_view), WatchUi.SLIDE_UP);
    }

    // Converts a named exercise menu item ID to the canonical display name
    // used by StrengthTracker and written to FIT fields.
    // Returns null for IDs handled separately (ex_exit, ex_generic).
    private function _nameForId(id as String) as String? {
        if (id.equals("ex_rest"))          { return "Rest"; }
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

// ─────────────────────────────────────────────────────────────────────────────
// GenericMetMenuDelegate
// Handles MET selection from the three-level Generic MET picker.
// On selection it encodes the MET value into the exercise name and starts the
// exercise, then closes all three open menus (Generic, Exercise, Segment).
// ─────────────────────────────────────────────────────────────────────────────
class GenericMetMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;

        // Each ID is "gmet_NN" where NN is MET × 10.  We encode this into the
        // exercise name as "Generic MET NN" so StrengthTracker._getMet() can
        // parse the integer suffix back to a float MET without extra properties.
        var name = _nameForMetId(id);
        if (name != null) {
            (_view as NexRunView)._strengthTracker.startExercise(name);
        }

        // Close all three menus: Generic MET picker, Exercise sub-menu, Segment menu.
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Generic MET picker
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Exercise sub-menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Segment menu
        WatchUi.requestUpdate();
    }

    // Maps a "gmet_NN" item ID to an encoded exercise name.
    // The integer suffix (NN = MET × 10) is what StrengthTracker parses in
    // _getMet() after stripping the "Generic MET " prefix.
    private function _nameForMetId(id as String) as String? {
        if (id.equals("gmet_50"))  { return "Generic MET 50"; }
        if (id.equals("gmet_60"))  { return "Generic MET 60"; }
        if (id.equals("gmet_70"))  { return "Generic MET 70"; }
        if (id.equals("gmet_80"))  { return "Generic MET 80"; }
        if (id.equals("gmet_90"))  { return "Generic MET 90"; }
        if (id.equals("gmet_100")) { return "Generic MET 100"; }
        if (id.equals("gmet_110")) { return "Generic MET 110"; }
        if (id.equals("gmet_120")) { return "Generic MET 120"; }
        return null;
    }
}
