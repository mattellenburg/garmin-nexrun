import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

// Renders the total-activity statistics screen (page 2).
// Shows time, distance, cardio-only average pace, and total calories in a
// four-row grid.  Max HR is shown in red alongside average HR.
//
// Expected stats dictionary keys:
//   :totalDistMiles   — Float, total GPS distance in miles
//   :totalTimeMs      — Number, activity timer in milliseconds
//   :calories         — Number, device-reported total calories
//   :cardioOnlySpeed  — Float, average m/s while in Cardio and moving
//   :maxHR            — Number, peak heart rate seen this activity
module TotalDisplay {
    function draw(dc, w, h, hr, stats as Dictionary) as Void {
        var totalDistMiles = stats[:totalDistMiles];
        var totalTimeMs = stats[:totalTimeMs];
        var calories = stats[:calories];
        var cardioOnlySpeed = stats[:cardioOnlySpeed];
        var maxHR = stats[:maxHR];

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            22,
            Graphics.FONT_XTINY,
            "TOTAL ACTIVITY",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setPenWidth(2);
        dc.drawLine(w * 0.2, 42, w * 0.8, 42);

        var col1 = w * 0.3;
        var col2 = w * 0.7;
        var row1 = 58;
        var row2 = 108;
        var row3 = 158;
        var row4 = 208;
        var labelDelta = 24; // Vertical gap between value and its label

        dc.setPenWidth(1);

        // Row 1 — Total elapsed time and total distance
        dc.drawText(
            col1,
            row1,
            Graphics.FONT_SMALL,
            CommonDisplay.formatTime(totalTimeMs / 1000),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            col1,
            row1 + labelDelta,
            Graphics.FONT_XTINY,
            "TIME",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.drawText(
            col2,
            row1,
            Graphics.FONT_SMALL,
            totalDistMiles.format("%.2f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            col2,
            row1 + labelDelta,
            Graphics.FONT_XTINY,
            "MILES",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Row 2 — Cardio-only average pace (minutes per mile/km)
        dc.drawText(
            col1,
            row2,
            Graphics.FONT_SMALL,
            _formatPace(cardioOnlySpeed),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            col1,
            row2 + labelDelta,
            Graphics.FONT_XTINY,
            "AVG PACE",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Calories live in the right column of row 2.
        dc.drawText(
            col2,
            row2,
            Graphics.FONT_SMALL,
            calories.toString(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            col2,
            row2 + labelDelta,
            Graphics.FONT_XTINY,
            "CALORIES",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Row 3 — Average and maximum heart rate
        var info = Activity.getActivityInfo();
        var avgHR =
            info != null && info.averageHeartRate != null
                ? info.averageHeartRate.toString()
                : "--";

        dc.drawText(
            col1,
            row3,
            Graphics.FONT_SMALL,
            avgHR,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            col1,
            row3 + labelDelta,
            Graphics.FONT_XTINY,
            "AVG HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            col2,
            row3,
            Graphics.FONT_SMALL,
            maxHR > 0 ? maxHR.toString() : "--",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            col2,
            row3 + labelDelta,
            Graphics.FONT_XTINY,
            "MAX HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Row 4 — Current heart rate (live, centered)
        var hrValue = hr instanceof Lang.Number ? hr : 0;
        var hrString = hrValue > 0 ? hrValue.toString() : "--";
        dc.drawText(
            w / 2,
            row4,
            Graphics.FONT_SMALL,
            hrString + " bpm",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            w / 2,
            row4 + labelDelta,
            Graphics.FONT_XTINY,
            "CURRENT HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Formats a speed in m/s to a min/mile or min/km pace string.
    // Returns "--:--" when speed is zero or effectively zero.
    function _formatPace(speedMps) as String {
        if (speedMps == null || speedMps < 0.05) {
            return "--:--";
        }
        var settings = System.getDeviceSettings();
        var isMetric = settings.distanceUnits == System.UNIT_METRIC;
        var secPer = (isMetric ? 1000.0 : 1609.34) / speedMps;
        return CommonDisplay.formatTime(secPer.toNumber());
    }
}
