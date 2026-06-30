import Toybox.Activity;
import Toybox.Lang;
import Toybox.WatchUi;

// Handles item selection from the segment-switcher menu (opened by the Back
// button while an activity is recording) and from the exercise sub-menu
// shown when the user taps "Exercise" inside a Strength segment.
//
// MENU HIERARCHY:
//   Segment menu  → Warmup | Cardio | Rest | Strength | Cool Down | Stretching
//                          └─ (when in Strength, idle/resting) Exercise ──►
//                          └─ (when in Strength, exercising)   Rest
//                                  ↑ in-strength rest shortcut; does NOT
//                                    switch segments — see "strength_rest" below.
//   Exercise menu → Rest | Exit | Battle Ropes | … | Tire Flips | Generic ──►
//   Generic menu  → MET 5.0 | MET 6.0 | … | MET 12.0
//
// SESSION TIMER MANAGEMENT:
//   Strength and Rest segments pause the recording timer (session.stop()) so
//   their dwell time is excluded from the FIT session avg_speed.  All other
//   segments resume the timer (session.start()).  This makes the avg pace
//   shown in Garmin Connect reflect only the time spent moving.
class NexRunMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view     as NexRunView;
    private var _session;                    // ActivityRecording.Session — nullable
    private var _delegate as NexRunDelegate; // Back-reference for timer management

    function initialize(view as NexRunView, session, delegate as NexRunDelegate) {
        Menu2InputDelegate.initialize();
        _view     = view;
        _session  = session;
        _delegate = delegate;
    }

    // ---- Segment menu selection ----

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        var v  = _view as NexRunView;

        // "exercise" is only present in Strength mode — push the exercise sub-menu.
        if (id.equals("exercise")) {
            _pushExerciseMenu();
            return;
        }

        // "strength_rest" is the context-sensitive top item shown only while a
        // real exercise is running in Strength mode.  It starts an in-strength
        // rest interval directly — no segment switch, no lap marker, no timer
        // pause/resume, since we're staying in Strength the whole time.
        if (id.equals("strength_rest")) {
            v._strengthTracker.stopExercise();
            v._strengthTracker.startExercise("Rest");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
            return;
        }

        // Write the FIT lap marker and reset lap-scoped fields.
        if (_session != null && _session.isRecording()) {
            _session.addLap();
            v._strengthTracker.resetLap();
            v.resetLapStats();
        }

        // Show the minimal 3-second segment-name overlay.
        v._showingSummary = true;
        v._summaryTimer   = 3;

        // Determine the target mode so we can adjust the session timer before
        // calling setMode().  setMode() itself does not touch the session.
        var newMode = $.STATE_WARMUP;
        if      (id.equals("cardio"))     { newMode = $.STATE_CARDIO; }
        else if (id.equals("rest"))       { newMode = $.STATE_REST; }
        else if (id.equals("strength"))   { newMode = $.STATE_STRENGTH; }
        else if (id.equals("cooldown"))   { newMode = $.STATE_COOLDOWN; }
        else if (id.equals("stretching")) { newMode = $.STATE_STRETCHING; }

        // Pause or resume the recording timer based on the target segment.
        // Strength and Rest pause so their time is excluded from avg pace in Connect.
        _delegate.applyTimerStateForMode(newMode);

        // Reset lap origin markers to "now" after the timer state change so
        // lap time starts from the correct moment.
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            v._lapStartTime = info.timerTime;
            if (info.elapsedDistance != null) {
                v._lapStartDistance = info.elapsedDistance;
            }
        }

        v.setMode(newMode);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }

    // ---- Exercise sub-menu ----

    // "Rest" is first so the user can quickly start an in-strength rest interval.
    // "Exit" is second to back out without starting anything.
    // "Generic" is last and pushes a MET-picker sub-menu.
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
// ExerciseMenuDelegate — exercise sub-menu selections.
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
            WatchUi.popView(WatchUi.SLIDE_DOWN); // close exercise menu only
            return;
        }
        if (id.equals("ex_generic")) {
            _pushGenericMetMenu(); // three-level; GenericMetMenuDelegate closes all
            return;
        }

        var name = _nameForId(id);
        if (name != null) {
            (_view as NexRunView)._strengthTracker.startExercise(name);
        }
        // Close exercise sub-menu and segment menu; return user to the watch face.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }

    // Subtitles show the nearest named exercise as a calibration reference.
    private function _pushGenericMetMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Generic MET" });
        menu.addItem(new WatchUi.MenuItem("MET 5.0",  "Light effort",        "gmet_50",  null));
        menu.addItem(new WatchUi.MenuItem("MET 6.0",  "Moderate effort",     "gmet_60",  null));
        menu.addItem(new WatchUi.MenuItem("MET 7.0",  "Moderate-vigorous",   "gmet_70",  null));
        menu.addItem(new WatchUi.MenuItem("MET 8.0",  "~ Burpees / Dips",    "gmet_80",  null));
        menu.addItem(new WatchUi.MenuItem("MET 9.0",  "~ Kettlebell / Sled", "gmet_90",  null));
        menu.addItem(new WatchUi.MenuItem("MET 10.0", "~ Battle Ropes",      "gmet_100", null));
        menu.addItem(new WatchUi.MenuItem("MET 11.0", "~ Pull-ups",          "gmet_110", null));
        menu.addItem(new WatchUi.MenuItem("MET 12.0", "~ Rope Climb",        "gmet_120", null));
        WatchUi.pushView(menu, new GenericMetMenuDelegate(_view), WatchUi.SLIDE_UP);
    }

    // Maps menu item ID to the canonical exercise name used by StrengthTracker.
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
// GenericMetMenuDelegate — encodes the chosen MET into the exercise name.
// All three menu levels are closed on selection so the user returns to the face.
// ─────────────────────────────────────────────────────────────────────────────
class GenericMetMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as NexRunView;

    function initialize(view as NexRunView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var name = _nameForMetId(item.getId() as String);
        if (name != null) {
            (_view as NexRunView)._strengthTracker.startExercise(name);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Generic MET picker
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Exercise sub-menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Segment menu
        WatchUi.requestUpdate();
    }

    // Encodes MET × 10 as an integer suffix in the exercise name.
    // StrengthTracker._getMet() parses "Generic MET NN" → MET = NN / 10.0.
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
