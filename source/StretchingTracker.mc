import Toybox.Lang;

// Stretching segment tracker.
// Displays only the elapsed lap time; no pace or distance is relevant here.
class StretchingTracker {

    function initialize(view as NexRunView) {}

    function reset() as Void {}

    function getDisplayData(info, lapDistM as Float) as Dictionary {
        // Return null for valueR to trigger the single-column layout in LapDisplay.
        return {
            :valueL => "STRETCHING",
            :labelL => "Relax & recover",
            :valueR => null,
            :labelR => null,
        };
    }
}
