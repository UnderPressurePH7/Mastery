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
        // View modes — cycle order: 0 → 1 → 2 → 3 → 4 → 0
        // 0 = mastery + marks        (screenshot 2)
        // 1 = mastery only           (screenshot 4)
        // 2 = marks only             (screenshot 3)
        // 3 = mastery + marks + graph(screenshot 5)
        // 4 = marks + graph          (screenshot 1)
        public static const MODE_BOTH:int        = 0;
        public static const MODE_MASTERY:int     = 1;
        public static const MODE_MARKS:int       = 2;
        public static const MODE_BOTH_GRAPH:int  = 3;
        public static const MODE_MARKS_GRAPH:int = 4;
        private static const VIEW_MODES:Array = [MODE_BOTH, MODE_MASTERY, MODE_MARKS, MODE_BOTH_GRAPH, MODE_MARKS_GRAPH];

        private static const PAD_H:int        = 12;
        private static const PAD_V:int        = 8;
        private static const ROW_HEIGHT:int   = 22;
        private static const ROW_GAP:int      = 2;
        private static const COL_COUNT:int    = 4;
        private static const COL_GAP:int      = 18;
        private static const ICON_W:int       = 24;
        private static const ICON_H:int       = 22;
        private static const ICON_GAP:int     = 4;
        private static const VALUE_W:int      = 56;
        private static const COL_WIDTH:int    = ICON_W + ICON_GAP + VALUE_W;
        private static const PANEL_MIN_W:int  = PAD_H * 2 + COL_WIDTH * COL_COUNT + COL_GAP * (COL_COUNT - 1);

        private static const GRAPH_TOP_GAP:int = 8;
        private static const GRAPH_LEFT:int    = 38;
        private static const GRAPH_W:int       = PANEL_MIN_W - GRAPH_LEFT - PAD_H;
        private static const GRAPH_H:int       = 88;
        private static const GRAPH_ROWS:int    = 6;
        private static const GRAPH_COLS:int    = 10;

        private static const FONT_FACE:String        = "$FieldFont";
        private static const FONT_SIZE_VALUE:int     = 14;
        private static const FONT_SIZE_PERCENT:int   = 13;
        private static const FONT_SIZE_AXIS:int      = 11;

        private static const BG_COLOR_TOP:uint   = 0x1E1E1E;
        private static const BG_COLOR_BOT:uint   = 0x111111;
        private static const BG_ALPHA_TOP:Number  = 0.67;
        private static const BG_ALPHA_BOT:Number  = 0.73;

        private static const COLOR_VALUE:uint   = 0xE8E8E8;
        private static const COLOR_DIM:uint     = 0x667788;
        private static const COLOR_PERCENT:uint = 0xB0BCC8;
        private static const COLOR_GRID:uint    = 0x7A8490;
        private static const COLOR_LINE:uint    = 0xF1F1F1;
        private static const COLOR_AXIS:uint    = 0xA8B2BC;
        private static const COLOR_DOT:uint     = 0xFFFFFF;

        private static const ICON_MASTERY_3RD:String = "img://gui/maps/icons/achievement/48x48/markOfMastery1.png";
        private static const ICON_MASTERY_2ND:String = "img://gui/maps/icons/achievement/48x48/markOfMastery2.png";
        private static const ICON_MASTERY_1ST:String = "img://gui/maps/icons/achievement/48x48/markOfMastery3.png";
        private static const ICON_MASTERY_ACE:String = "img://gui/maps/icons/achievement/48x48/markOfMastery4.png";

        private static const BOUNDARY_GAP:int    = 10;
        private static const DRAG_DELAY:int      = 150;
        private static const DRAG_THRESHOLD:int  = 20;
        private static const CLICK_THRESHOLD:int = 6;

        private static const ICONS:Array          = [ICON_MASTERY_3RD, ICON_MASTERY_2ND, ICON_MASTERY_1ST, ICON_MASTERY_ACE];
        private static const PERCENT_LABELS:Array  = ["65%", "85%", "95%", "100%"];

        private var _background:Shape;
        private var _graphLayer:Shape;
        private var _dragHit:Sprite;

        private var _xpIcon:Array;
        private var _xpValue:Array;
        private var _moePercent:Array;
        private var _moeValue:Array;
        private var _axisLabels:Array;

        private var _textShadow:DropShadowFilter;
        private var _matrix:Matrix;

        private var _disposed:Boolean    = false;
        private var _offset:Array        = [100, 100];
        private var _panelWidth:int      = PANEL_MIN_W;
        private var _panelHeight:int     = 0;

        private var _clickPoint:Point;
        private var _clickOffset:Point;
        private var _reusablePoint:Point;
        private var _isDragging:Boolean  = false;
        private var _isDragTest:Boolean  = false;
        private var _dragTimeout:uint    = 0;

        private var _xp:Array            = [0, 0, 0, 0];
        private var _moe:Array           = [0, 0, 0, 0];
        private var _battleHistory:Array = [];
        private var _currentMark:Number  = NaN;
        private var _hasXp:Boolean       = false;
        private var _hasMoe:Boolean      = false;
        private var _hasGraph:Boolean    = false;
        private var _isLoading:Boolean   = false;

        private var _strLoading:String   = "...";
        private var _strNoData:String    = "N/A";
        private var _viewMode:int        = MODE_BOTH;

        public function MasteryPanelComponent()
        {
            super();
            mouseEnabled  = false;
            mouseChildren = true;

            _clickPoint    = new Point();
            _clickOffset   = new Point();
            _reusablePoint = new Point();
            _matrix        = new Matrix();
            _textShadow    = new DropShadowFilter(1, 45, 0x000000, 0.8, 2, 2, 1.2, 1);

            _background = new Shape();
            _background.filters = [new GlowFilter(0x000000, 0.4, 6, 6, 1, 1)];
            addChild(_background);

            _graphLayer = new Shape();
            addChild(_graphLayer);

            _xpIcon     = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_VALUE);
            _xpValue    = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_VALUE);
            _moePercent = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_PERCENT);
            _moeValue   = _createRowFields(COL_COUNT, TextFieldAutoSize.LEFT, FONT_SIZE_VALUE);
            _axisLabels = _createRowFields(4, TextFieldAutoSize.RIGHT, FONT_SIZE_AXIS);

            _createDragHit();
            _setupDragListeners();
            _layout();
        }

        // ── Public API ────────────────────────────────────────────────────

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

        public function setBattleHistory(values:Array, currentMark:Number):void
        {
            if (_disposed) return;
            _battleHistory = [];
            if (values != null)
            {
                for (var i:int = 0; i < values.length; i++)
                    _battleHistory.push(Number(values[i]));
            }
            _currentMark = currentMark;
            _hasGraph = (_battleHistory.length > 1);
            _layout();
        }

        public function setViewMode(mode:int):void
        {
            if (_disposed) return;
            if (VIEW_MODES.indexOf(mode) == -1) mode = MODE_BOTH;
            _viewMode = mode;
            _layout();
        }

        public function setLoading():void
        {
            if (_disposed) return;
            _hasXp = false; _hasMoe = false; _hasGraph = false;
            _isLoading = true;
            _layout();
        }

        public function clearData():void
        {
            if (_disposed) return;
            _hasXp = false; _hasMoe = false; _hasGraph = false;
            _battleHistory = [];
            _currentMark = NaN;
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

        // ── Layout ────────────────────────────────────────────────────────

        private function _layout():void
        {
            if (_disposed) return;

            var showMastery:Boolean = (_viewMode == MODE_BOTH || _viewMode == MODE_MASTERY || _viewMode == MODE_BOTH_GRAPH);
            var showMarks:Boolean   = (_viewMode == MODE_BOTH || _viewMode == MODE_MARKS   || _viewMode == MODE_BOTH_GRAPH || _viewMode == MODE_MARKS_GRAPH);
            var showGraph:Boolean   = (_viewMode == MODE_BOTH_GRAPH || _viewMode == MODE_MARKS_GRAPH);

            _panelWidth = PANEL_MIN_W;
            var y:int = PAD_V;

            if (showMastery)
            {
                _layoutMasteryRow(y);
                y += ROW_HEIGHT + ROW_GAP;
            }
            else
            {
                _hideRow(_xpIcon);
                _hideRow(_xpValue);
            }

            if (showMarks)
            {
                _layoutMarksRow(y);
                y += ROW_HEIGHT + ROW_GAP;
            }
            else
            {
                _hideRow(_moePercent);
                _hideRow(_moeValue);
            }

            if (showGraph)
            {
                _layoutGraph(y + GRAPH_TOP_GAP);
                y += GRAPH_TOP_GAP + GRAPH_H + PAD_V;
            }
            else
            {
                _graphLayer.graphics.clear();
                _hideRow(_axisLabels);
                y += PAD_V;
            }

            _panelHeight = y;
            _drawBackground();
            _redrawDragHit();
            _syncPosition();
        }

        private function _layoutMasteryRow(rowY:int):void
        {
            for (var i:int = 0; i < COL_COUNT; i++)
            {
                var colX:int   = PAD_H + i * (COL_WIDTH + COL_GAP);
                var valueX:int = colX + ICON_W + ICON_GAP;

                var iconTf:TextField = _xpIcon[i] as TextField;
                iconTf.visible = true;
                iconTf.htmlText = "<img src='" + ICONS[i] + "' width='" + ICON_W + "' height='" + ICON_H + "'/>";
                iconTf.x = colX;
                iconTf.y = rowY - 2;

                var xpTf:TextField = _xpValue[i] as TextField;
                xpTf.visible = true;
                xpTf.htmlText = _fmt(_xpCellText(i), FONT_SIZE_VALUE, _hasXp ? COLOR_VALUE : COLOR_DIM);
                xpTf.x = valueX;
                xpTf.y = rowY + 1;
            }
        }

        private function _layoutMarksRow(rowY:int):void
        {
            for (var i:int = 0; i < COL_COUNT; i++)
            {
                var colX:int   = PAD_H + i * (COL_WIDTH + COL_GAP);
                var valueX:int = colX + ICON_W + ICON_GAP;

                var pctTf:TextField = _moePercent[i] as TextField;
                pctTf.visible = true;
                pctTf.htmlText = _fmt(PERCENT_LABELS[i] as String, FONT_SIZE_PERCENT, COLOR_PERCENT);
                pctTf.x = colX;
                pctTf.y = rowY + 2;

                var moeTf:TextField = _moeValue[i] as TextField;
                moeTf.visible = true;
                moeTf.htmlText = _fmt(_moeCellText(i), FONT_SIZE_VALUE, _hasMoe ? COLOR_VALUE : COLOR_DIM);
                moeTf.x = valueX;
                moeTf.y = rowY + 1;
            }
        }

        private function _layoutGraph(topY:int):void
        {
            var g:Graphics = _graphLayer.graphics;
            g.clear();

            var left:Number   = PAD_H + GRAPH_LEFT;
            var top:Number    = topY;
            var right:Number  = left + GRAPH_W;
            var bottom:Number = top + GRAPH_H;
            var rowStep:Number = GRAPH_H / GRAPH_ROWS;
            var colStep:Number = GRAPH_W / GRAPH_COLS;

            var values:Array = (_battleHistory && _battleHistory.length > 0) ? _battleHistory.concat() : [];
            if (values.length == 0 && !isNaN(_currentMark))
                values = [_currentMark];

            // Dynamic Y scale
            var minV:Number = 0.0, maxV:Number = 100.0;
            if (values.length > 0)
            {
                minV = maxV = Number(values[0]);
                for (var i:int = 1; i < values.length; i++)
                {
                    if (Number(values[i]) < minV) minV = Number(values[i]);
                    if (Number(values[i]) > maxV) maxV = Number(values[i]);
                }
            }
            minV = Math.floor(minV) - 1;
            maxV = Math.ceil(maxV)  + 1;
            if (maxV - minV < 6)
            {
                var center:Number = (maxV + minV) * 0.5;
                minV = Math.floor(center - 3);
                maxV = Math.ceil(center + 3);
            }
            if (minV < 0)    minV = 0;
            if (maxV > 100)  maxV = 100;
            if (maxV <= minV) maxV = minV + 6;

            // Grid lines
            g.lineStyle(1, COLOR_GRID, 0.25);
            for (i = 0; i <= GRAPH_ROWS; i++)
            {
                var gy:Number = top + i * rowStep;
                g.moveTo(left, gy);
                g.lineTo(right, gy);
            }
            for (i = 0; i <= GRAPH_COLS; i++)
            {
                var gx:Number = left + i * colStep;
                g.moveTo(gx, top);
                g.lineTo(gx, bottom);
            }

            // Y-axis labels (4 labels: top, 1/3, 2/3, bottom)
            for (i = 0; i < _axisLabels.length; i++)
            {
                var labelTf:TextField = _axisLabels[i] as TextField;
                labelTf.visible = true;
                var ratio:Number = Number(i) / Number(_axisLabels.length - 1);
                var labelVal:Number = maxV - (maxV - minV) * ratio;
                labelTf.htmlText = _fmt(int(Math.round(labelVal)).toString() + "%", FONT_SIZE_AXIS, COLOR_AXIS);
                labelTf.x = PAD_H + GRAPH_LEFT - 4;
                labelTf.y = top + ratio * GRAPH_H - 8;
            }

            if (values.length < 1) return;

            // Build screen points
            var pts:Array = [];
            for (i = 0; i < values.length; i++)
            {
                var px:Number = left + colStep * 0.5 + i * colStep;
                var py:Number = bottom - ((Number(values[i]) - minV) / (maxV - minV)) * GRAPH_H;
                pts.push(new Point(px, py));
            }

            // Line
            if (pts.length > 1)
            {
                g.lineStyle(2, COLOR_LINE, 0.95);
                g.moveTo(pts[0].x, pts[0].y);
                for (i = 1; i < pts.length; i++)
                    g.lineTo(pts[i].x, pts[i].y);
            }

            // Square dots per battle
            g.lineStyle(1, COLOR_DOT, 0.9);
            g.beginFill(COLOR_DOT, 0.95);
            for (i = 0; i < pts.length; i++)
                g.drawRect(pts[i].x - 2.5, pts[i].y - 2.5, 5, 5);
            g.endFill();
        }

        // ── Cell text ─────────────────────────────────────────────────────

        private function _xpCellText(i:int):String
        {
            if (_isLoading) return _strLoading;
            if (!_hasXp)    return _strNoData;
            var v:int = int(_xp[i]);
            if (v <= 0)     return _strNoData;
            return _fmtNum(v);
        }

        private function _moeCellText(i:int):String
        {
            if (_isLoading) return _strLoading;
            if (!_hasMoe)   return _strNoData;
            var v:int = int(_moe[i]);
            if (v <= 0)     return _strNoData;
            return _fmtNum(v);
        }

        // ── Drawing ───────────────────────────────────────────────────────

        private function _drawBackground():void
        {
            var g:Graphics = _background.graphics;
            g.clear();
            _matrix.createGradientBox(_panelWidth, _panelHeight, Math.PI / 2, 0, 0);
            g.beginGradientFill(GradientType.LINEAR,
                [BG_COLOR_TOP, BG_COLOR_BOT],
                [BG_ALPHA_TOP, BG_ALPHA_BOT],
                [0, 255], _matrix);
            g.drawRoundRect(0, 0, _panelWidth, _panelHeight, 4, 4);
            g.endFill();
        }

        // ── Drag hit ──────────────────────────────────────────────────────

        private function _createDragHit():void
        {
            _dragHit = new Sprite();
            _dragHit.buttonMode   = true;
            _dragHit.useHandCursor = true;
            addChild(_dragHit);
            _redrawDragHit();
        }

        private function _redrawDragHit():void
        {
            if (!_dragHit) return;
            _dragHit.graphics.clear();
            _dragHit.graphics.beginFill(0x000000, 0.0);
            _dragHit.graphics.drawRect(0, 0, _panelWidth, _panelHeight);
            _dragHit.graphics.endFill();
        }

        // ── Listeners ────────────────────────────────────────────────────

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
                stage.addEventListener(MouseEvent.MOUSE_UP,   _onDragMouseUp);
                stage.addEventListener(MouseEvent.MOUSE_MOVE, _onDragMouseMove);
            }
        }

        private function _removeStageListeners():void
        {
            if (stage)
            {
                stage.removeEventListener(MouseEvent.MOUSE_UP,   _onDragMouseUp);
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
            _clickPoint.x  = stage.mouseX;
            _clickPoint.y  = stage.mouseY;
            _clickOffset.x = this.x - _clickPoint.x;
            _clickOffset.y = this.y - _clickPoint.y;
            _isDragTest = true;
            _clearDragTimeout();
            _dragTimeout = setTimeout(_beginDrag, DRAG_DELAY);
            _addStageListeners();
        }

        private function _beginDrag():void
        {
            _isDragTest  = false;
            _isDragging  = true;
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
            var distSq:Number = (stage.mouseX - _clickPoint.x) * (stage.mouseX - _clickPoint.x)
                              + (stage.mouseY - _clickPoint.y) * (stage.mouseY - _clickPoint.y);
            _clearDragTimeout();
            if (_isDragging)
            {
                _offset[0] = int(this.x);
                _offset[1] = int(this.y);
                dispatchEvent(new MasteryPanelEvent(MasteryPanelEvent.OFFSET_CHANGED, _offset));
            }
            else if (_isDragTest && distSq <= CLICK_THRESHOLD * CLICK_THRESHOLD)
            {
                _cycleViewMode();
            }
            _isDragTest = false;
            _isDragging = false;
            _removeStageListeners();
        }

        private function _cycleViewMode():void
        {
            var idx:int = VIEW_MODES.indexOf(_viewMode);
            if (idx < 0) idx = 0;
            idx = (idx + 1) % VIEW_MODES.length;
            _viewMode = int(VIEW_MODES[idx]);
            _layout();
            dispatchEvent(new MasteryPanelEvent(MasteryPanelEvent.VIEW_MODE_CHANGED, _viewMode));
        }

        // ── Position ──────────────────────────────────────────────────────

        private function _clampToScreen(px:Number, py:Number):void
        {
            var sw:int = (stage != null && stage.stageWidth  > 0) ? stage.stageWidth  : 1920;
            var sh:int = (stage != null && stage.stageHeight > 0) ? stage.stageHeight : 1080;
            _reusablePoint.x = int(Math.max(BOUNDARY_GAP, Math.min(sw - _panelWidth  - BOUNDARY_GAP, px)));
            _reusablePoint.y = int(Math.max(BOUNDARY_GAP, Math.min(sh - _panelHeight - BOUNDARY_GAP, py)));
        }

        private function _syncPosition():void
        {
            if (_isDragging || _disposed) return;
            _clampToScreen(_offset[0], _offset[1]);
            this.x = _reusablePoint.x;
            this.y = _reusablePoint.y;
        }

        // ── Helpers ───────────────────────────────────────────────────────

        private function _createRowFields(count:int, autoSize:String, fontSize:int):Array
        {
            var arr:Array = [];
            for (var i:int = 0; i < count; i++)
            {
                var tf:TextField = new TextField();
                tf.selectable   = false;
                tf.mouseEnabled  = false;
                tf.autoSize      = autoSize;
                tf.multiline     = false;
                tf.filters       = [_textShadow];
                addChild(tf);
                arr.push(tf);
            }
            return arr;
        }

        private function _hideRow(arr:Array):void
        {
            for (var i:int = 0; i < arr.length; i++)
                TextField(arr[i]).visible = false;
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
            var abs:int     = neg ? -value : value;
            var s:String    = String(abs);
            var result:String = "";
            var count:int   = 0;
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
