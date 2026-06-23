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

        // Each entry: [mode constant, color, start angle, end angle].
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
                dc.setPenWidth(thickness);
                dc.setColor(seg[:color], Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawArc(cx, cy, radius + thickness / 2, Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
                dc.drawArc(cx, cy, radius - thickness / 2, Graphics.ARC_CLOCKWISE, seg[:s], seg[:e]);
                var sRad = Math.toRadians(seg[:s]);
                var eRad = Math.toRadians(seg[:e]);
                var rOut = radius + thickness / 2;
                var rIn  = radius - thickness / 2;
                dc.drawLine(cx + rIn * Math.cos(sRad), cy - rIn * Math.sin(sRad),
                            cx + rOut * Math.cos(sRad), cy - rOut * Math.sin(sRad));
                dc.drawLine(cx + rIn * Math.cos(eRad), cy - rIn * Math.sin(eRad),
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
            Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLUE, Graphics.COLOR_GREEN,
            Graphics.COLOR_ORANGE,  Graphics.COLOR_RED,
        ];
        dc.setPenWidth(thickness);
        for (var i = 0; i < 5; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius,
                Graphics.ARC_COUNTER_CLOCKWISE,
                225 + i * 18, 225 + (i + 1) * 18);
        }
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
}
