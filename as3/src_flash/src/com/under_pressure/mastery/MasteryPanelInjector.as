package com.under_pressure.mastery
{
    import flash.display.MovieClip;
    import flash.events.Event;
    import net.wg.infrastructure.base.AbstractView;
    import net.wg.infrastructure.events.LoaderEvent;
    import net.wg.infrastructure.managers.impl.ContainerManagerBase;

    public class MasteryPanelInjector extends AbstractView
    {
        private var _panel:MasteryPanelComponent = null;

        public var py_onDragEnd:Function          = null;
        public var py_onPanelReady:Function       = null;
        public var py_onViewModeChanged:Function  = null;

        private var _configDone:Boolean    = false;
        private var _pendingCalls:Array    = [];
        private var _notifyFrameCount:int  = 0;

        public function MasteryPanelInjector()
        {
            super();
        }

        override protected function configUI():void
        {
            super.configUI();

            _createPanel();
            _configDone = true;
            _replayPendingCalls();

            var cm:ContainerManagerBase = App.containerMgr as ContainerManagerBase;
            if (cm && cm.loader)
                cm.loader.addEventListener(LoaderEvent.VIEW_LOADED, _onViewLoaded);

            if (App.instance && App.instance.stage)
                App.instance.stage.addEventListener(Event.RESIZE, _onResize);

            _notifyFrameCount = 0;
            addEventListener(Event.ENTER_FRAME, _onNotifyFrame);
        }

        override protected function nextFrameAfterPopulateHandler():void
        {
            super.nextFrameAfterPopulateHandler();
            if (parent != App.instance)
                (App.instance as MovieClip).addChild(this);
        }

        override protected function onDispose():void
        {
            removeEventListener(Event.ENTER_FRAME, _onNotifyFrame);
            var cm:ContainerManagerBase = App.containerMgr as ContainerManagerBase;
            if (cm && cm.loader)
                cm.loader.removeEventListener(LoaderEvent.VIEW_LOADED, _onViewLoaded);
            if (App.instance && App.instance.stage)
                App.instance.stage.removeEventListener(Event.RESIZE, _onResize);
            _destroyPanel();
            _pendingCalls = [];
            py_onDragEnd         = null;
            py_onPanelReady      = null;
            py_onViewModeChanged = null;
            _configDone = false;
            super.onDispose();
        }

        private function _onNotifyFrame(event:Event):void
        {
            _notifyFrameCount++;
            if (_notifyFrameCount < 3) return;
            removeEventListener(Event.ENTER_FRAME, _onNotifyFrame);
            if (py_onPanelReady != null)
                py_onPanelReady();
        }

        private function _onResize(event:Event):void
        {
            if (_panel) _panel.updatePosition();
        }

        private function _onViewLoaded(event:LoaderEvent):void
        {
            if (_panel) _panel.updatePosition();
        }

        private function _createPanel():void
        {
            if (_panel) return;
            _panel = new MasteryPanelComponent();
            _panel.addEventListener(MasteryPanelEvent.OFFSET_CHANGED,    _onOffsetChanged);
            _panel.addEventListener(MasteryPanelEvent.VIEW_MODE_CHANGED, _onViewModeChanged);
            addChild(_panel);
        }

        private function _destroyPanel():void
        {
            if (_panel)
            {
                _panel.removeEventListener(MasteryPanelEvent.OFFSET_CHANGED,    _onOffsetChanged);
                _panel.removeEventListener(MasteryPanelEvent.VIEW_MODE_CHANGED, _onViewModeChanged);
                _panel.dispose();
                if (_panel.parent) _panel.parent.removeChild(_panel);
                _panel = null;
            }
        }

        private function _replayPendingCalls():void
        {
            if (_pendingCalls.length == 0) return;
            var calls:Array = _pendingCalls;
            _pendingCalls = [];
            for (var i:int = 0; i < calls.length; i++)
            {
                var call:Object = calls[i];
                var fn:Function = call.fn as Function;
                if (fn != null) fn.apply(null, call.args);
            }
        }

        private function _onOffsetChanged(event:MasteryPanelEvent):void
        {
            if (py_onDragEnd != null) py_onDragEnd(event.data);
        }

        private function _onViewModeChanged(event:MasteryPanelEvent):void
        {
            if (py_onViewModeChanged != null) py_onViewModeChanged(event.data);
        }

        // ── AS3 callable from Python ──────────────────────────────────────

        public function as_setMasteryData(third:int, second:int, first:int, ace:int):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setMasteryData, args: [third, second, first, ace]}); return; }
            if (_panel) _panel.setMasteryData(third, second, first, ace);
        }

        public function as_setMoeData(p65:int, p85:int, p95:int, p100:int):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setMoeData, args: [p65, p85, p95, p100]}); return; }
            if (_panel) _panel.setMoeData(p65, p85, p95, p100);
        }

        public function as_setBattleHistory(values:Array, currentMark:Number):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setBattleHistory, args: [values, currentMark]}); return; }
            if (_panel) _panel.setBattleHistory(values, currentMark);
        }

        public function as_setViewMode(mode:int):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setViewMode, args: [mode]}); return; }
            if (_panel) _panel.setViewMode(mode);
        }

        public function as_setLoading():void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setLoading, args: []}); return; }
            if (_panel) _panel.setLoading();
        }

        public function as_clearData():void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_clearData, args: []}); return; }
            if (_panel) _panel.clearData();
        }

        public function as_setVisible(value:Boolean):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setVisible, args: [value]}); return; }
            if (_panel) _panel.setVisibleState(value);
        }

        public function as_setPosition(offset:Array):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setPosition, args: [offset]}); return; }
            if (_panel) _panel.setPositionOffset(offset);
        }

        public function as_setLocalization(data:Object):void
        {
            if (!_configDone) { _pendingCalls.push({fn: this.as_setLocalization, args: [data]}); return; }
            if (_panel) _panel.setLocalization(data);
        }
    }
}
