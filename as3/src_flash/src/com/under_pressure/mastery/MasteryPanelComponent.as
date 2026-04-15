package com.under_pressure.mastery
{
    import flash.display.GradientType;
    import flash.display.Graphics;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.events.MouseEvent;
    import flash.filters.DropShadowFilter;
    import flash.filters.GlowFilter;
    import flash.geom.Matrix;
    import flash.geom.Point;
    import flash.text.TextField;
    import flash.text.TextFieldAutoSize;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;

    public class MasteryPanelComponent extends Sprite
    {
        private static const PAD_H:int = 12;
        private static const PAD_V:int = 8;
        private static const ROW_HEIGHT:int = 22;
        private static const ROW_GAP:int = 2;
        private static const COL_COUNT:int = 4;
        private static const COL_GAP:int = 10;
        private static const ICON_W:int = 24;
        private static const ICON_H:int = 22;
        private static const ICON_GAP:int = 4;
        private static const VALUE_W:int = 56;
        private static const COL_WIDTH:int = ICON_W + ICON_GAP + VALUE_W;
        private static const PANEL_WIDTH:int = PAD_H * 2 + COL_WIDTH * COL_COUNT + COL_GAP * (COL_COUNT - 1);
        private static const PANEL_HEIGHT:int = PAD_V * 2 + ROW_HEIGHT * 2 + ROW_GAP;

        private static const FONT_FACE:String = "$FieldFont";
        private static const FONT_SIZE_VALUE:int = 14;
        private static const FONT_SIZE_PERCENT:int = 13;

        private static const BG_COLOR_TOP:uint = 0x1E1E1E;
        private static const BG_COLOR_BOT:uint = 0x111111;
        private static const BG_ALPHA_TOP:Number = 0.67;
        private static const BG_ALPHA_BOT:Number = 0.73;

        private static const COLOR_VALUE:uint = 0xE8E8E8;
        private static const COLOR_DIM:uint = 0x667788;
        private static const COLOR_PERCENT:uint = 0xB0BCC8;

        private static const ICON_MASTERY_3RD:String = "img://gui/maps/icons/achievement/48x48/markOfMastery1.png";
        private static const ICON_MASTERY_2ND:String = "img://gui/maps/icons/achievement/48x48/markOfMastery2.png";
        private static const ICON_MASTERY_1ST:String = "img://gui/maps/icons/achievement/48x48/markOfMastery3.png";
        private static const ICON_MASTERY_ACE:String = "img://gui/maps/icons/achievement/48x48/markOfMastery4.png";

        private static const BOUNDARY_GAP:int = 10;
        private static const DRAG_DELAY:int = 150;
        private static const DRAG_THRESHOLD:int = 20;

        private var _background:Shape;
        private var _dragHit:Sprite;

        private var _xpIcon:Array;
        private var _xpValue:Array;
        private var _moePercent:Array;
        private var _moeValue:Array;

        private var _textShadow:DropShadowFilter;
        private var _matrix:Matrix;

        private var _disposed:Boolean = false;
        private var _collapsed:Boolean = false;
        private var _offset:Array = [100, 100];

        private var _clickPoint:Point;
        private var _clickOffset:Point;
        private var _reusablePoint:Point;
        private var _isDragging:Boolean = false;
        private var _isDragTest:Boolean = false;
        private var _dragTimeout:uint = 0;

        private var _xp:Array = [0, 0, 0, 0];
        private var _moe:Array = [0, 0, 0, 0];
        private var _hasXp:Boolean = false;
        private var _hasMoe:Boolean = false;
        private var _isLoading:Boolean = false;

        private var _strLoading:String = "...";
        private var _strNoData:String = "N/A";

        private static const ICONS:Array = [ICON_MASTERY_3RD, ICON_MASTERY_2ND, ICON_MASTERY_1ST, ICON_MASTERY_ACE];
        private static const PERCENT_LABELS:Array = ["65%", "85%", "95%", "100%"];

        public function MasteryPanelComponent()
        {
            super();
            mouseEnabled = false;
            mouseChildren = true;

            _clickPoint = new Point();
            _clickOffset = new Point();
            _reusablePoint = new Point();
            _matrix = new Matrix();
            _textShadow = new DropShadowFilter(1, 45, 0x000000, 0.8, 2, 2, 1.2, 1);

            _background = new Shape();
            _background.filters = [new GlowFilter(0x000000, 0.4, 6, 6, 1, 1)];
            addChild(_background);

            _xpIcon = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_VALUE);
            _xpValue = _createRowFields(COL_COUNT, TextFieldAutoSize.RIGHT, FONT_SIZE_VALUE);
            _moePercent = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_PERCENT);
            _moeValue = _createRowFields(COL_COUNT, TextFieldAutoSize.RIGHT, FONT_SIZE_VALUE);

            _createDragHit();
            _setupDragListeners();
            _layout();
        }

        public function setMasteryData(third:int, second:int, first:int, ace:int):void
        {
            if (_disposed) return;
            _xp[0] = third; _xp[1] = second; _xp[2] = first; _xp[3] = ace;
            _hasXp = (third > 0 || second > 0 || first > 0 || ace > 0);
            _isLoading = false;
            _layout();
        }

        public function setMoeData(p65:int, p85:int, p95:int, p100:int):void
        {
            if (_disposed) return;
            _moe[0] = p65; _moe[1] = p85; _moe[2] = p95; _moe[3] = p100;
            _hasMoe = (p65 > 0 || p85 > 0 || p95 > 0 || p100 > 0);
            _isLoading = false;
            _layout();
        }

        public function setLoading():void
        {
            if (_disposed) return;
            _hasXp = false;
            _hasMoe = false;
            _isLoading = true;
            _layout();
        }

        public function clearData():void
        {
            if (_disposed) return;
            _hasXp = false;
            _hasMoe = false;
            _isLoading = false;
            _layout();
        }

        public function setVisibleState(value:Boolean):void
        {
            if (_disposed) return;
            this.visible = value;
        }

        public function setPositionOffset(offset:Array):void
        {
            if (_disposed) return;
            if (offset && offset.length >= 2)
            {
                _offset[0] = int(offset[0]);
                _offset[1] = int(offset[1]);
            }
            _syncPosition();
        }

        public function setCollapsedState(value:Boolean):void
        {
            if (_disposed) return;
            _collapsed = value;
        }

        public function setLocalization(data:Object):void
        {
            if (_disposed || !data) return;
            if (data.loading) _strLoading = String(data.loading);
            if (data.noData)  _strNoData  = String(data.noData);
            _layout();
        }

        public function updatePosition():void
        {
            if (_disposed) return;
            _syncPosition();
        }

        public function dispose():void
        {
            if (_disposed) return;
            _disposed = true;
            _teardownDragListeners();
            _clearDragTimeout();
        }

        private function _layout():void
        {
            if (_disposed) return;

            var rowTopY:int = PAD_V;
            var rowBotY:int = rowTopY + ROW_HEIGHT + ROW_GAP;

            for (var i:int = 0; i < COL_COUNT; i++)
            {
                var colX:int = PAD_H + i * (COL_WIDTH + COL_GAP);
                var iconX:int = colX;
                var valueRight:int = colX + COL_WIDTH;

                var iconTf:TextField = _xpIcon[i] as TextField;
                iconTf.htmlText = "<img src='" + ICONS[i] + "' width='" + ICON_W + "' height='" + ICON_H + "'/>";
                iconTf.x = iconX;
                iconTf.y = rowTopY - 2;

                var xpTf:TextField = _xpValue[i] as TextField;
                var xpValColor:uint = _hasXp ? COLOR_VALUE : COLOR_DIM;
                xpTf.htmlText = _fmt(_xpCellText(i), FONT_SIZE_VALUE, xpValColor);
                xpTf.x = valueRight - xpTf.width;
                xpTf.y = rowTopY + 1;

                var pctTf:TextField = _moePercent[i] as TextField;
                pctTf.htmlText = _fmt(PERCENT_LABELS[i] as String, FONT_SIZE_PERCENT, COLOR_PERCENT);
                pctTf.x = iconX;
                pctTf.y = rowBotY + 2;

                var moeTf:TextField = _moeValue[i] as TextField;
                var moeValColor:uint = _hasMoe ? COLOR_VALUE : COLOR_DIM;
                moeTf.htmlText = _fmt(_moeCellText(i), FONT_SIZE_VALUE, moeValColor);
                moeTf.x = valueRight - moeTf.width;
                moeTf.y = rowBotY + 1;
            }

            _drawBackground();
            _redrawDragHit();
            _syncPosition();
        }

        private function _xpCellText(i:int):String
        {
            if (_isLoading) return _strLoading;
            if (!_hasXp) return _strNoData;
            var v:int = int(_xp[i]);
            if (v <= 0) return _strNoData;
            return _fmtNum(v);
        }

        private function _moeCellText(i:int):String
        {
            if (_isLoading) return _strLoading;
            if (!_hasMoe) return _strNoData;
            var v:int = int(_moe[i]);
            if (v <= 0) return _strNoData;
            return _fmtNum(v);
        }

        private function _drawBackground():void
        {
            var g:Graphics = _background.graphics;
            g.clear();
            _matrix.createGradientBox(PANEL_WIDTH, PANEL_HEIGHT, Math.PI / 2, 0, 0);
            g.beginGradientFill(
                GradientType.LINEAR,
                [BG_COLOR_TOP, BG_COLOR_BOT],
                [BG_ALPHA_TOP, BG_ALPHA_BOT],
                [0, 255],
                _matrix
            );
            g.drawRoundRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT, 4, 4);
            g.endFill();
        }

        private function _createDragHit():void
        {
            _dragHit = new Sprite();
            _dragHit.buttonMode = true;
            _dragHit.useHandCursor = true;
            addChild(_dragHit);
            _redrawDragHit();
        }

        private function _redrawDragHit():void
        {
            if (!_dragHit) return;
            _dragHit.graphics.clear();
            _dragHit.graphics.beginFill(0x000000, 0.0);
            _dragHit.graphics.drawRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT);
            _dragHit.graphics.endFill();
        }

        private function _setupDragListeners():void
        {
            if (!_dragHit) return;
            _dragHit.addEventListener(MouseEvent.MOUSE_DOWN, _onDragMouseDown);
        }

        private function _teardownDragListeners():void
        {
            if (_dragHit) _dragHit.removeEventListener(MouseEvent.MOUSE_DOWN, _onDragMouseDown);
            _removeStageListeners();
        }

        private function _addStageListeners():void
        {
            if (stage)
            {
                stage.addEventListener(MouseEvent.MOUSE_UP, _onDragMouseUp);
                stage.addEventListener(MouseEvent.MOUSE_MOVE, _onDragMouseMove);
            }
        }

        private function _removeStageListeners():void
        {
            if (stage)
            {
                stage.removeEventListener(MouseEvent.MOUSE_UP, _onDragMouseUp);
                stage.removeEventListener(MouseEvent.MOUSE_MOVE, _onDragMouseMove);
            }
        }

        private function _clearDragTimeout():void
        {
            if (_dragTimeout != 0) { clearTimeout(_dragTimeout); _dragTimeout = 0; }
        }

        private function _onDragMouseDown(e:MouseEvent):void
        {
            if (_disposed || !stage) return;
            _clickPoint.x = stage.mouseX;
            _clickPoint.y = stage.mouseY;
            _clickOffset.x = this.x - _clickPoint.x;
            _clickOffset.y = this.y - _clickPoint.y;
            _isDragTest = true;
            _clearDragTimeout();
            _dragTimeout = setTimeout(_beginDrag, DRAG_DELAY);
            _addStageListeners();
        }

        private function _beginDrag():void
        {
            _isDragTest = false;
            _isDragging = true;
            _dragTimeout = 0;
        }

        private function _onDragMouseMove(e:MouseEvent):void
        {
            if (_disposed || !stage) return;
            if (!_isDragging && _isDragTest)
            {
                var dx:Number = stage.mouseX - _clickPoint.x;
                var dy:Number = stage.mouseY - _clickPoint.y;
                if (dx * dx + dy * dy > DRAG_THRESHOLD * DRAG_THRESHOLD)
                {
                    _clearDragTimeout();
                    _beginDrag();
                    return;
                }
            }
            if (_isDragging)
            {
                _clampToScreen(_clickOffset.x + stage.mouseX, _clickOffset.y + stage.mouseY);
                this.x = _reusablePoint.x;
                this.y = _reusablePoint.y;
            }
        }

        private function _onDragMouseUp(e:MouseEvent):void
        {
            _clearDragTimeout();
            if (_isDragging)
            {
                _offset[0] = int(this.x);
                _offset[1] = int(this.y);
                dispatchEvent(new MasteryPanelEvent(MasteryPanelEvent.OFFSET_CHANGED, _offset));
            }
            _isDragTest = false;
            _isDragging = false;
            _removeStageListeners();
        }

        private function _clampToScreen(px:Number, py:Number):void
        {
            var sw:int = App.appWidth > 0 ? App.appWidth : 1920;
            var sh:int = App.appHeight > 0 ? App.appHeight : 1080;
            _reusablePoint.x = int(Math.max(BOUNDARY_GAP, Math.min(sw - PANEL_WIDTH - BOUNDARY_GAP, px)));
            _reusablePoint.y = int(Math.max(BOUNDARY_GAP, Math.min(sh - PANEL_HEIGHT - BOUNDARY_GAP, py)));
        }

        private function _syncPosition():void
        {
            if (_isDragging || _disposed) return;
            _clampToScreen(_offset[0], _offset[1]);
            this.x = _reusablePoint.x;
            this.y = _reusablePoint.y;
        }

        private function _createRowFields(count:int, autoSize:String, fontSize:int):Array
        {
            var arr:Array = [];
            for (var i:int = 0; i < count; i++)
            {
                var tf:TextField = new TextField();
                tf.selectable = false;
                tf.mouseEnabled = false;
                tf.autoSize = autoSize;
                tf.multiline = false;
                tf.filters = [_textShadow];
                addChild(tf);
                arr.push(tf);
            }
            return arr;
        }

        private function _fmt(text:String, size:int, color:uint):String
        {
            return '<font face="' + FONT_FACE + '" size="' + size + '" color="' + _hex(color) + '"><b>' + text + '</b></font>';
        }

        private static function _hex(color:uint):String
        {
            var h:String = color.toString(16).toUpperCase();
            while (h.length < 6) h = "0" + h;
            return "#" + h;
        }

        private function _fmtNum(value:int):String
        {
            var neg:Boolean = value < 0;
            var abs:int = neg ? -value : value;
            var s:String = String(abs);
            var result:String = "";
            var count:int = 0;
            for (var i:int = s.length - 1; i >= 0; i--)
            {
                if (count > 0 && count % 3 == 0) result = " " + result;
                result = s.charAt(i) + result;
                count++;
            }
            return neg ? ("-" + result) : result;
        }
    }
}
