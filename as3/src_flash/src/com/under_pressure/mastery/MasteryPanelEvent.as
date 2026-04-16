package com.under_pressure.mastery
{
    import flash.events.Event;

    public class MasteryPanelEvent extends Event
    {
        public static const OFFSET_CHANGED:String    = "MasteryPanel.offsetChanged";
        public static const VIEW_MODE_CHANGED:String = "MasteryPanel.viewModeChanged";

        public var data:*;

        public function MasteryPanelEvent(type:String, data:* = null, bubbles:Boolean = false, cancelable:Boolean = false)
        {
            super(type, bubbles, cancelable);
            this.data = data;
        }

        override public function clone():Event
        {
            return new MasteryPanelEvent(type, data, bubbles, cancelable);
        }
    }
}
