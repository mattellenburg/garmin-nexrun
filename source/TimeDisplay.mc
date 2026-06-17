import Toybox.Graphics;
import Toybox.System;

// Renders the time-of-day screen (page 3).
module TimeDisplay {
    function draw(dc, w, h) {
        var clockTime = System.getClockTime();
        var hour = clockTime.hour;
        var ampm = hour >= 12 ? " PM" : " AM";
        hour = hour % 12;
        hour = hour == 0 ? 12 : hour;

        var timeString =
            hour.format("%d") + ":" + clockTime.min.format("%02d") + ampm;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            w / 2,
            h / 2,
            Graphics.FONT_LARGE,
            timeString,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
