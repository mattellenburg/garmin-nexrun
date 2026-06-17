import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.UserProfile;

// Stateless drawing helpers shared by all display pages and overlays.
// Every function accepts all data it needs as parameters so this module has
// no dependency on view internals and can be called from any context.
module CommonDisplay {

    // Formats an integer number of seconds as M:SS or H:MM:SS.
    function formatTime(seconds) as String {
        if (seconds == null || seconds < 0) { return "0:00"; }
        var hrs = seconds / 3600;
        var min = (seconds % 3600) / 60;
        var sec = seconds % 60;
        if (hrs > 0) {
            return Lang.format("$1$:$2$:$3$",
                [hrs, min.format("%02d"), sec.format("%02d")]);
        }
        return Lang.format("$1$:$2$", [min, sec.format("%02d")]);
    }

    // Draws the six-segment mode-indicator arc near the top of the watch face.
    // The active segment is highlighted at full width; inactive segments are
    // drawn as thin outlines so the user always knows which phase is current.
    function drawModeArc(dc, w, h, currentMode) as Void {
        var cx        = w / 2;
        var cy        = h / 2;
        var radius    = w / 2 - 7;
        var thickness = 8;

        // Each segment descriptor: mode constant, color, start and end angle.
        // Angles are in Garmin's coordinate system (0° = 3 o'clock, CW).
        var segments = [
            { :mode => $.STATE_WARMUP,    :color => Graphics.COLOR_GREEN,  :s => 150, :e => 132 },
            { :mode => $.STATE_CARDIO,    :color => Graphics.COLOR_ORANGE, :s => 130, :e => 112 },
            { :mode => $.STATE_REST,      :color => Graphics.COLOR_YELLOW, :s => 110, :e =>  92 },
            { :mode => $.STATE_STRENGTH,  :color => Graphics.COLOR_RED,    :s =>  88, :e =>  70 },
            { :mode => $.STATE_COOLDOWN,  :color => Graphics.COLOR_BLUE,   :s =>  68, :e =>  50 },
            { :mode => $.STATE_STRETCHING,:color => Graphics.COLOR_PURPLE, :s =>  48, :e =>  30 },
        ];

        for (var i = 0; i < segments.size(); i++) {
            var seg = segments[i];
            if (currentMode == seg[:mode]) {
                // Active: solid filled arc
                dc.setPenWidth(thickness);
                dc.setColor(seg[:color], Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius,
                    Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
            } else {
                // Inactive: thin double-line outline with end caps
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawArc(cx, cy, radius + thickness / 2,
                    Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
                dc.drawArc(cx, cy, radius - thickness / 2,
                    Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
                // End caps
                var sRad = Math.toRadians(seg[:s]);
                var eRad = Math.toRadians(seg[:e]);
                var rOut = radius + thickness / 2;
                var rIn  = radius - thickness / 2;
                dc.drawLine(
                    cx + rIn * Math.cos(sRad), cy - rIn * Math.sin(sRad),
                    cx + rOut * Math.cos(sRad), cy - rOut * Math.sin(sRad));
                dc.drawLine(
                    cx + rIn * Math.cos(eRad), cy - rIn * Math.sin(eRad),
                    cx + rOut * Math.cos(eRad), cy - rOut * Math.sin(eRad));
            }
        }
    }

    // Draws the five-zone HR arc along the bottom of the watch face.
    // A white tick mark moves along the arc to show the current zone position.
    function drawHRZArc(dc, w, h, hrValue) as Void {
        var cx        = w / 2;
        var cy        = h / 2;
        var radius    = w / 2 - 7;
        var thickness = 10;

        var colors = [
            Graphics.COLOR_LT_GRAY,  // Zone 1
            Graphics.COLOR_BLUE,     // Zone 2
            Graphics.COLOR_GREEN,    // Zone 3
            Graphics.COLOR_ORANGE,   // Zone 4
            Graphics.COLOR_RED,      // Zone 5
        ];

        dc.setPenWidth(thickness);
        for (var i = 0; i < 5; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius,
                Graphics.ARC_COUNTER_CLOCKWISE,
                225 + i * 18, 225 + (i + 1) * 18);
        }

        // Tick mark — shows HR position within the zone bands.
        if (hrValue > 0) {
            var zones       = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
            var currentZone = 0.0;
            if (hrValue < zones[0]) {
                currentZone = hrValue.toFloat() / zones[0];
            } else {
                for (var i = 0; i < 5; i++) {
                    if (hrValue < zones[i + 1] || i == 4) {
                        currentZone = i + 1 +
                            (hrValue - zones[i]).toFloat() /
                            (zones[i + 1] - zones[i]);
                        break;
                    }
                }
            }
            var angle = 225 + currentZone * 18;
            if (angle > 315) { angle = 315; }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            var rad = Math.toRadians(angle);
            dc.drawLine(
                cx + (radius - thickness) * Math.cos(rad),
                cy - (radius - thickness) * Math.sin(rad),
                cx + (radius + thickness) * Math.cos(rad),
                cy - (radius + thickness) * Math.sin(rad));
        }
    }

    // Draws a simple six-point heart polygon at (x, y) with the given size.
    function drawHeartIcon(dc, x, y, size) as Void {
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        var s = size;
        dc.fillPolygon([
            [x,         y + s / 4],
            [x - s / 2, y - s / 4],
            [x - s / 4, y - s / 2],
            [x,         y - s / 4],
            [x + s / 4, y - s / 2],
            [x + s / 2, y - s / 4],
        ]);
    }

    // Draws the full-screen segment-transition summary overlay.
    // Shown for several seconds after the user switches segments so they can
    // review their previous segment stats before the new one begins.
    //
    // Special case: lastMode == -1 signals activity start (no previous segment).
    function drawSummaryOverlay(
        dc, w, h,
        currentMode,
        lastLapTime,  lastAvgHR,
        lastMode,
        lastLapPace,  lastLapDist
    ) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var modeNames = ["WARMUP","CARDIO","REST","STRENGTH","COOL DOWN","STRETCHING"];

        dc.drawText(w / 2, h * 0.12, Graphics.FONT_SMALL,
            "Now: " + modeNames[currentMode],
            Graphics.TEXT_JUSTIFY_CENTER);

        // Activity-start special case: no previous segment data to show.
        if (lastMode == -1) {
            dc.drawText(w / 2, h * 0.45, Graphics.FONT_XTINY,
                "Activity started", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.82, Graphics.FONT_XTINY,
                "Press any button to dismiss",
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Previous segment header
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.30, Graphics.FONT_XTINY,
            "Prev: " + modeNames[lastMode],
            Graphics.TEXT_JUSTIFY_CENTER);

        // Time and HR from the finished segment
        var timeStr = Lang.format("$1$:$2$", [
            (lastLapTime / 60).format("%02d"),
            (lastLapTime % 60).format("%02d"),
        ]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.44, Graphics.FONT_XTINY,
            timeStr + "  |  HR " + lastAvgHR,
            Graphics.TEXT_JUSTIFY_CENTER);

        // Cardio pace + distance (only meaningful for running-type segments)
        if (lastMode == $.STATE_CARDIO || lastMode == $.STATE_WARMUP ||
            lastMode == $.STATE_COOLDOWN) {
            var pace = (lastLapPace != null && !lastLapPace.equals(""))
                       ? lastLapPace : "--:--";
            var dist = lastLapDist != null ? lastLapDist : 0.0;
            dc.drawText(w / 2, h * 0.58, Graphics.FONT_SMALL,
                pace + "  " + dist.format("%.2f") + " mi",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.84, Graphics.FONT_XTINY,
            "Press any button to dismiss",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
