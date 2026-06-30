import Toybox.Graphics;
import Toybox.Lang;

// Renders the main lap data screen (page 1).
// Accepts a display-data dictionary from the active tracker so it has no
// direct knowledge of which segment type is running.
//
// Dictionary keys:
//   :valueL     — left data value (required)
//   :labelL     — left label (required)
//   :valueR     — right data value; null collapses to single-column layout
//   :labelR     — right label
//   :valueB     — optional bottom value (e.g. overall pace in Cardio)
//   :labelB     — optional bottom label
//   :labelColor — optional Graphics color for labL/valL text; defaults to
//                 white.  Lets a tracker call out a state visually (e.g.
//                 StrengthTracker uses this to distinguish an active
//                 exercise from an in-strength rest interval) without
//                 LapDisplay needing any tracker-specific knowledge.
module LapDisplay {

    // Draws the full lap screen: timer bar, two (or one) data fields,
    // an optional bottom field, HR readout, and HR zone arc.
    function draw(dc, w, h, lapTimeSec, hr, displayData as Dictionary) as Void {
        var valL  = displayData[:valueL];
        var labL  = displayData[:labelL];
        var valR  = displayData[:valueR];
        var labR  = displayData[:labelR];
        var valB  = displayData[:valueB];        // optional
        var labB  = displayData[:labelB];         // optional
        var labelColor = displayData[:labelColor] != null
                         ? displayData[:labelColor] : Graphics.COLOR_WHITE;

        // --- Lap timer at the top ---
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 20, Graphics.FONT_NUMBER_MEDIUM,
            CommonDisplay.formatTime(lapTimeSec),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 78, Graphics.FONT_XTINY,
            "LAP TIME", Graphics.TEXT_JUSTIFY_CENTER);

        // --- Middle data fields ---
        // Single-column when valR is null; two-column otherwise.
        // labelColor tints the primary (left/single) value+label so a tracker
        // can flag an important state change (e.g. resting vs. exercising).
        if (valR == null || valR.equals("")) {
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 115, Graphics.FONT_MEDIUM,
                valL + " " + labL,
                Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // Left column
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 4, 105, Graphics.FONT_LARGE,
                valL, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 4, 140, Graphics.FONT_XTINY,
                labL, Graphics.TEXT_JUSTIFY_CENTER);
            // Right column always white — labelColor only applies to the left
            // field, which is where trackers report their primary state.
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText((w * 3) / 4, 105, Graphics.FONT_LARGE,
                valR, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText((w * 3) / 4, 140, Graphics.FONT_XTINY,
                labR, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // --- Optional bottom field (overall pace for Cardio) ---
        if (valB != null && !valB.equals("")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 165, Graphics.FONT_SMALL,
                valB, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, 188, Graphics.FONT_XTINY,
                labB, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // --- Heart rate readout and zone arc ---
        var hrValue  = hr instanceof Lang.Number ? hr : 0;
        var hrString = hrValue > 0 ? hrValue.toString() : "--";
        var hrY      = h * 0.72;

        CommonDisplay.drawHeartIcon(dc, w * 0.3, hrY + 25, 14);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, hrY, Graphics.FONT_NUMBER_MILD,
            hrString, Graphics.TEXT_JUSTIFY_CENTER);

        CommonDisplay.drawHRZArc(dc, w, h, hrValue);
    }
}
