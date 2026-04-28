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
        public static const MODE_BOTH:int        = 0;
        public static const MODE_MASTERY:int     = 1;
        public static const MODE_MARKS:int       = 2;
        public static const MODE_BOTH_GRAPH:int  = 3;
        public static const MODE_MARKS_GRAPH:int = 4;
        private static const VIEW_MODES:Array = [MODE_BOTH, MODE_MASTERY, MODE_MARKS, MODE_BOTH_GRAPH, MODE_MARKS_GRAPH];

        private static const PAD_H:int        = 12;
        private static const PAD_V:int        = 6;
        private static const ROW_HEIGHT:int   = 20;
        private static const ROW_GAP:int      = 1;
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
        private static const COLOR_LABEL:uint   = 0xFFFFFF;
        private static const FONT_SIZE_LABEL:int = 11;

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
        private var _markLabel:TextField;

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

            _markLabel = new TextField();
            _markLabel.selectable  = false;
            _markLabel.mouseEnabled = false;
            _markLabel.autoSize    = TextFieldAutoSize.LEFT;
            _markLabel.multiline   = false;
            _markLabel.filters     = [_textShadow];
            _markLabel.visible     = false;
            addChild(_markLabel);

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
            _hasGraph = (_battleHistory.length >= 1);
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
                if (_markLabel) _markLabel.visible = false;
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

            var i:int;
            var left:Number   = PAD_H + GRAPH_LEFT;
            var top:Number    = topY;
            var right:Number  = left + GRAPH_W;
            var bottom:Number = top + GRAPH_H;
            var rowStep:Number = GRAPH_H / GRAPH_ROWS;
            var colStep:Number = GRAPH_W / GRAPH_COLS;

            var values:Array = (_battleHistory && _battleHistory.length > 0) ? _battleHistory.concat() : [];
            if (values.length == 0 && !isNaN(_currentMark))
                values = [_currentMark];

            for (i = 0; i <= GRAPH_ROWS; i++)
            {
                var gy:Number = top + i * rowStep;
                if (i == GRAPH_ROWS)
                {
                    g.lineStyle(0.5, COLOR_GRID, 0.22);
                    g.moveTo(left, gy);
                    g.lineTo(right, gy);
                }
                else
                {
                    g.lineStyle(0.5, COLOR_GRID, 0.08);
                    var dashX:Number = left;
                    while (dashX + 2 < right)
                    {
                        g.moveTo(dashX, gy);
                        g.lineTo(dashX + 2, gy);
                        dashX += 5;
                    }
                }
            }
            g.lineStyle(NaN);

            if (values.length < 1)
            {
                if (_markLabel) _markLabel.visible = false;
                return;
            }

            var PILL_RESERVE:Number = 38;
            var WINDOW:int = 10;
            var AXIS_STEP:Number = 2.0;
            var AXIS_ROWS:int   = 4;

            var currentVal:Number = !isNaN(_currentMark) ? _currentMark : Number(values[values.length - 1]);
            var axisBot:Number = Math.floor(currentVal / AXIS_STEP) * AXIS_STEP - AXIS_STEP;
            var axisTop:Number = axisBot + AXIS_ROWS * AXIS_STEP;
            if (axisBot < 0)  { axisBot = 0;   axisTop = AXIS_ROWS * AXIS_STEP; }
            if (axisTop > 100) { axisTop = 100; axisBot = 100 - AXIS_ROWS * AXIS_STEP; }
            var dynRange:Number = axisTop - axisBot;
            var inRange:Array = [];
            for (i = 0; i < values.length; i++)
            {
                var val:Number = Number(values[i]);
                if (val >= axisBot && val <= axisTop)
                    inRange.push(val);
            }
            if (inRange.length == 0)
                inRange.push(currentVal);
            var winValues:Array = inRange.length > WINDOW
                ? inRange.slice(inRange.length - WINDOW)
                : inRange;

            var winCount:int = winValues.length;
            var LEFT_PAD:Number = 28;
            var filtStep:Number = winCount > 1
                ? (GRAPH_W - PILL_RESERVE - LEFT_PAD) / (winCount - 1)
                : 0;

            var pts:Array = [];
            for (i = 0; i < winCount; i++)
            {
                var fv:Number = Number(winValues[i]);
                var px:Number = winCount > 1
                    ? left + LEFT_PAD + i * filtStep
                    : left + (GRAPH_W - PILL_RESERVE);
                var rawPy:Number = bottom - ((fv - axisBot) / dynRange) * GRAPH_H;
                var py:Number = Math.max(top, Math.min(bottom, rawPy));
                pts.push(new Point(px, py));
            }
            var actualRows:int = int((axisTop - axisBot) / AXIS_STEP);
            var labelStep:int = Math.ceil(actualRows / AXIS_ROWS);
            if (labelStep < 1) labelStep = 1;
            var labelIdx:int = 0;
            for (i = 0; i <= actualRows; i++)
            {
                if (i % labelStep != 0 && i != actualRows) continue;
                if (labelIdx >= _axisLabels.length) break;
                var axisVal:Number = axisBot + i * AXIS_STEP;
                var labelTf2:TextField = _axisLabels[_axisLabels.length - 1 - labelIdx] as TextField;
                if (labelTf2)
                {
                    labelTf2.visible = true;
                    labelTf2.htmlText = _fmt(int(Math.round(axisVal)).toString() + "%", FONT_SIZE_AXIS, COLOR_AXIS);
                    labelTf2.x = PAD_H + GRAPH_LEFT - 4;
                    labelTf2.y = bottom - (i / actualRows) * GRAPH_H - 8;
                }
                labelIdx++;
            }
            for (i = labelIdx; i < _axisLabels.length; i++)
            {
                var hideTf:TextField = _axisLabels[i] as TextField;
                if (hideTf) hideTf.visible = false;
            }
            if (pts.length >= 2)
            {
                g.endFill();
                var areaAlphas:Array  = [0.12, 0.0];
                var areaColors:Array  = [COLOR_LINE, COLOR_LINE];
                var areaRatios:Array  = [0, 255];
                var areaMatrix:Matrix = new Matrix();
                areaMatrix.createGradientBox(GRAPH_W, GRAPH_H, Math.PI / 2, left, top);
                g.beginGradientFill(GradientType.LINEAR, areaColors, areaAlphas, areaRatios, areaMatrix);
                g.moveTo(pts[0].x, pts[0].y);
                var midX:Number = (pts[0].x + pts[1].x) * 0.5;
                var midY:Number = (pts[0].y + pts[1].y) * 0.5;
                g.lineTo(midX, midY);
                for (i = 1; i < pts.length - 1; i++)
                {
                    var nextMidX:Number = (pts[i].x + pts[i+1].x) * 0.5;
                    var nextMidY:Number = (pts[i].y + pts[i+1].y) * 0.5;
                    g.curveTo(pts[i].x, pts[i].y, nextMidX, nextMidY);
                }
                g.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
                g.lineTo(pts[pts.length - 1].x, bottom);
                g.lineTo(pts[0].x, bottom);
                g.endFill();

                g.lineStyle(1.5, COLOR_LINE, 0.95);
                g.moveTo(pts[0].x, pts[0].y);
                midX = (pts[0].x + pts[1].x) * 0.5;
                midY = (pts[0].y + pts[1].y) * 0.5;
                g.lineTo(midX, midY);
                for (i = 1; i < pts.length - 1; i++)
                {
                    nextMidX = (pts[i].x + pts[i+1].x) * 0.5;
                    nextMidY = (pts[i].y + pts[i+1].y) * 0.5;
                    g.curveTo(pts[i].x, pts[i].y, nextMidX, nextMidY);
                }
                g.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
                g.endFill();
                g.lineStyle(NaN);
            }

            for (i = 0; i < pts.length - 1; i++)
            {
                g.lineStyle(NaN);
                g.beginFill(COLOR_DOT, 0.7);
                g.drawCircle(pts[i].x, pts[i].y, 2);
                g.endFill();
            }

            var lastPt:Point = pts[pts.length - 1] as Point;
            g.lineStyle(1, COLOR_DOT, 0.3);
            g.beginFill(0x000000, 0);
            g.drawCircle(lastPt.x, lastPt.y, 5);
            g.endFill();
            g.lineStyle(0);
            g.beginFill(COLOR_DOT, 0.95);
            g.drawCircle(lastPt.x, lastPt.y, 2.5);
            g.endFill();

            var dashH:Number = 4;
            var gapH:Number  = 3;
            var dashY:Number = lastPt.y + 4;
            g.lineStyle(0.5, COLOR_DOT, 0.2);
            while (dashY + dashH < bottom)
            {
                g.moveTo(lastPt.x, dashY);
                g.lineTo(lastPt.x, dashY + dashH);
                dashY += dashH + gapH;
            }

            var labelVal:Number = !isNaN(_currentMark) ? _currentMark : Number(values[values.length - 1]);
            var labelStr:String = labelVal.toFixed(2) + "%";
            _markLabel.htmlText = _fmt(labelStr, FONT_SIZE_LABEL, COLOR_LABEL);

            var calloutEndX:Number = lastPt.x + 14;
            var calloutEndY:Number = lastPt.y - 14;
            if (calloutEndY < top + 2) calloutEndY = top + 2;

            var labelX:Number = calloutEndX + 2;
            var labelY:Number = calloutEndY - _markLabel.height * 0.5;

            if (labelX + _markLabel.width + 8 > right)
            {
                calloutEndX = lastPt.x - 14;
                calloutEndY = lastPt.y - 14;
                labelX = calloutEndX - _markLabel.width - 8;
            }
            if (labelY < top) labelY = top;
            if (labelY + _markLabel.height > bottom) labelY = bottom - _markLabel.height;

            g.lineStyle(0.75, COLOR_DOT, 0.35);
            g.moveTo(lastPt.x + 2, lastPt.y - 2);
            g.lineTo(calloutEndX, calloutEndY);

            var pillPad:Number = 3;
            var pillW:Number   = _markLabel.width + pillPad * 2;
            var pillH:Number   = _markLabel.height;
            var pillX:Number   = labelX - pillPad;
            var pillY:Number   = labelY;
            var pillR:Number   = pillH * 0.5;
            g.lineStyle(0.75, 0xC8B97A, 0.4);
            g.beginFill(0x0A0E12, 0.93);
            g.drawRoundRect(pillX, pillY, pillW, pillH, pillR * 2, pillR * 2);
            g.endFill();

            _markLabel.x = labelX;
            _markLabel.y = labelY;
            _markLabel.visible = true;
        }

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
