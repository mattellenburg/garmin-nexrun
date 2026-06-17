import Toybox.Lang;

// Rest segment tracker.
// Shows only elapsed lap time so the user can pace their recovery interval.
class RestTracker {

    function initialize(view as NexRunView) {}

    function reset() as Void {}

    function getDisplayData(info, lapDistM as Float) as Dictionary {
        // Returning null for valueR triggers the single-column layout.
        return {
            :valueL => "REST",
            :labelL => "Recovery",
            :valueR => null,
            :labelR => null,
        };
    }
}
