import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Final post-save summary screen.  Shown after the user chooses "Save" from
// the Paused menu, displaying the four headline stats for the whole activity:
// total time, total distance, total calories, and average heart rate.
//
// The screen auto-dismisses after savedSummarySeconds (configurable via
// properties.xml / settings.xml) by calling System.exit(), which is the only
// way to fully close a Connect IQ watch-app and return to the watch face.
class ActivitySummaryView extends WatchUi.View {

    private var _stats as Dictionary;
    private var _timer as Timer.Timer?;

    // stats keys expected: :totalTimeMs, :totalDistMiles, :totalCalories, :avgHR
    function initialize(stats as Dictionary) {
        View.initialize();
        _stats = stats;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // No layout resource needed — drawn entirely in onUpdate().
    }

    function onShow() as Void {
        var seconds = _getSavedSummarySeconds();
        _timer = new Timer.Timer();
        _timer.start(method(:onAutoExit), seconds * 1000, false);
    }

    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    // Single-shot callback: closes the app and returns to the watch face.
    function onAutoExit() as Void {
        System.exit();
    }

    private function _getSavedSummarySeconds() as Number {
        var v = Application.Properties.getValue("savedSummarySeconds");
        return v != null ? v as Number : 8;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_SMALL,
            "ACTIVITY SAVED", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setPenWidth(2);
        dc.drawLine(w * 0.2, h * 0.18, w * 0.8, h * 0.18);

        var totalTimeMs    = _stats[:totalTimeMs]    != null ? _stats[:totalTimeMs]    : 0;
        var totalDistMiles = _stats[:totalDistMiles] != null ? _stats[:totalDistMiles] : 0.0;
        var totalCalories  = _stats[:totalCalories]  != null ? _stats[:totalCalories]  : 0;
        var avgHR          = _stats[:avgHR]          != null ? _stats[:avgHR]          : 0;

        var col1 = w * 0.3;
        var col2 = w * 0.7;
        var row1 = h * 0.34;
        var row2 = h * 0.60;
        var labelDelta = 24;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        // Row 1 — total time and total distance
        dc.drawText(col1, row1, Graphics.FONT_MEDIUM,
            CommonDisplay.formatTime(totalTimeMs / 1000), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(col1, row1 + labelDelta, Graphics.FONT_XTINY,
            "TIME", Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(col2, row1, Graphics.FONT_MEDIUM,
            totalDistMiles.format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(col2, row1 + labelDelta, Graphics.FONT_XTINY,
            "MILES", Graphics.TEXT_JUSTIFY_CENTER);

        // Row 2 — total calories and average heart rate
        dc.drawText(col1, row2, Graphics.FONT_MEDIUM,
            totalCalories.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(col1, row2 + labelDelta, Graphics.FONT_XTINY,
            "CALORIES", Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(col2, row2, Graphics.FONT_MEDIUM,
            avgHR > 0 ? avgHR.toString() : "--", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(col2, row2 + labelDelta, Graphics.FONT_XTINY,
            "AVG HR", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.90, Graphics.FONT_XTINY,
            "Closing...", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// Any button press exits immediately rather than waiting for the auto-dismiss
// timer, so an attentive user isn't forced to wait out the full countdown.
class ActivitySummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean { System.exit(); return true; }
    function onBack()   as Boolean { System.exit(); return true; }
    function onMenu()   as Boolean { System.exit(); return true; }
}
