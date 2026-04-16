# -*- coding: utf-8 -*-
import cPickle
import functools
import json
import logging
import os
import time
import zlib
from collections import deque

import BigWorld
import constants
from Account import PlayerAccount
from CurrentVehicle import g_currentVehicle
from PlayerEvents import g_playerEvents
from gui.Scaleform.framework import g_entitiesFactories, ScopeTemplates, ViewSettings
from gui.Scaleform.framework.entities.View import View
from gui.Scaleform.framework.managers.loaders import SFViewLoadParams
from gui.Scaleform.lobby_entry import getLobbyStateMachine
from gui.shared.personality import ServicesLocator
from frameworks.wulf import WindowLayer

try:
    from messenger.proto.events import g_messengerEvents
except ImportError:
    g_messengerEvents = None

try:
    from messenger.formatters.service_channel import SYS_MESSAGE_TYPE
except ImportError:
    SYS_MESSAGE_TYPE = None

try:
    from gui.shared import g_eventBus
except ImportError:
    g_eventBus = None

try:
    from gui.shared.events import GUICommonEvent
except ImportError:
    GUICommonEvent = None

try:
    from helpers import dependency
except ImportError:
    dependency = None

try:
    from skeletons.gui.impl import IGuiLoader
except ImportError:
    IGuiLoader = None

try:
    from frameworks.wulf import WindowStatus
except ImportError:
    WindowStatus = None

logger = logging.getLogger('under_pressure.mastery')
logger.setLevel(logging.DEBUG if os.path.isfile('.debug_mods') else logging.ERROR)

__version__ = '0.0.6'

_LINKAGE = 'MasteryPanelInjector'
_SWF = 'MasteryPanel.swf'

_L10N_DIR = 'mods/under_pressure.mastery'
_L10N_FALLBACK = 'en'
_l10n = {}

_API_APP_ID = 'bce57ac20af6b67b08be09fd66847ed9'
_API_URL_TEMPLATE = (
    'https://api.worldoftanks.%s/wot/tanks/mastery/'
    '?application_id=' + _API_APP_ID +
    '&distribution=%s&percentile=%s&tank_id=%s'
)
_XP_PERCENTILES_QUERY = u'50%2C80%2C95%2C99'
_MOE_PERCENTILES_QUERY = u'65%2C85%2C95%2C100'
_PERCENTILE_TO_KEY = (
    (u'50', 'thirdClass'),
    (u'80', 'secondClass'),
    (u'95', 'firstClass'),
    (u'99', 'aceTanker'),
)
_MOE_PERCENTILE_TO_KEY = (
    (u'65',  'p65'),
    (u'85',  'p85'),
    (u'95',  'p95'),
    (u'100', 'p100'),
)

_INJECT_RETRY_DELAY = 0.5
_INJECT_MAX_ATTEMPTS = 30
_API_TIMEOUT = 5.0
_API_MAX_ATTEMPTS = 3
_API_RETRY_BASE_DELAY = 2.0
_MAX_HISTORY = 10
_DEFAULT_VIEW_MODE = 0

try:
    _prefsFilePath = BigWorld.wg_getPreferencesFilePath()
except AttributeError:
    _prefsFilePath = BigWorld.getPreferencesFilePath()

_CACHE_DIR = os.path.normpath(os.path.join(os.path.dirname(_prefsFilePath), 'mods', 'mastery'))
_CACHE_FILE = os.path.join(_CACHE_DIR, 'cache.dat')
_CACHE_VERSION = 3
_CACHE_TTL_SECONDS = 3 * 24 * 3600
_CACHE_SAVE_DEBOUNCE = 3.0


def _cancelCallbackSafe(cbid):
    try:
        if cbid is not None:
            BigWorld.cancelCallback(cbid)
    except (AttributeError, ValueError):
        pass


def _loadLocalization():
    global _l10n
    try:
        from helpers import getClientLanguage
        lang = getClientLanguage() or _L10N_FALLBACK
    except Exception:
        lang = _L10N_FALLBACK
    for tryLang in (lang, _L10N_FALLBACK):
        path = _L10N_DIR + '/' + tryLang + '.json'
        try:
            import ResMgr
            section = ResMgr.openSection(path)
            if section is not None:
                _l10n = json.loads(section.asBinary)
                logger.debug('l10n loaded: %s (%d keys)', tryLang, len(_l10n))
                return
        except Exception:
            logger.exception('l10n failed for %s', tryLang)
    logger.debug('l10n: no file found, using defaults')


def _tr(key, default=u''):
    return _l10n.get(key, default)


def _getDefaultHangarStateCls():
    try:
        from gui.impl.lobby.hangar.states import DefaultHangarState
        return DefaultHangarState
    except Exception:
        logger.exception('DefaultHangarState import failed')
        return None


def _getApiDomain():
    realm = unicode(getattr(constants, 'AUTH_REALM', u'EU')).upper()
    if 'NA' in realm:
        return 'com'
    if 'ASIA' in realm:
        return 'asia'
    return 'eu'


def _buildApiUrl(tankID, distribution, percentilesQuery):
    return _API_URL_TEMPLATE % (_getApiDomain(), distribution, percentilesQuery, tankID)


def _findTankRecord(container, tankID):
    if not isinstance(container, dict):
        return None
    for key in (tankID, str(tankID), unicode(tankID)):
        if key in container:
            return container.get(key)
    return None


def _extractPercentile(source, percentile):
    for key in (percentile, str(percentile)):
        if key in source:
            try:
                return int(source.get(key))
            except (TypeError, ValueError):
                return None
    return None


def _parseApiResponse(payload, tankID, mapping):
    if not isinstance(payload, dict):
        return None
    data = payload.get('data')
    if not isinstance(data, dict):
        return None
    distribution = data.get('distribution')
    if not isinstance(distribution, dict):
        distribution = data
    record = _findTankRecord(distribution, tankID)
    if not isinstance(record, dict):
        return None
    result = {}
    for percentile, key in mapping:
        result[key] = _extractPercentile(record, percentile)
    if all(v is None for v in result.itervalues()):
        return None
    return result


def _safeFloat(value):
    try:
        return float(value)
    except Exception:
        return None


def _readMarkPercent(vehicle):
    if vehicle is None:
        return None
    candidates = []
    for attr in ('marksOnGun', 'damageRating', 'movingAvgDamage'):
        if hasattr(vehicle, attr):
            candidates.append(getattr(vehicle, attr))
    dossier = getattr(vehicle, 'publicInfo', None)
    if dossier is not None:
        for attr in ('marksOnGun', 'damageRating'):
            if hasattr(dossier, attr):
                candidates.append(getattr(dossier, attr))
    descr = getattr(vehicle, 'descriptor', None)
    if descr is not None:
        for attr in ('marksOnGun', 'damageRating'):
            if hasattr(descr, attr):
                candidates.append(getattr(descr, attr))

    for value in candidates:
        number = _safeFloat(value)
        if number is None:
            continue
        if 0.0 <= number <= 100.0:
            return round(number, 2)
        if 0.0 <= number <= 1.0:
            return round(number * 100.0, 2)
    return None


def _readMarkForTankID(tankID):
    if tankID is None:
        return None
    try:
        items = ServicesLocator.itemsCache.items
    except Exception:
        return None
    if items is None:
        return None
    try:
        vehicle = items.getItemByCD(int(tankID))
    except Exception:
        return None
    if vehicle is None:
        return None
    return _readMarkPercent(vehicle)


class MasteryPanelInjectorView(View):
    _g_controller = None

    def _populate(self):
        super(MasteryPanelInjectorView, self)._populate()
        if MasteryPanelInjectorView._g_controller:
            MasteryPanelInjectorView._g_controller._onInjectorReady(self)

    def _dispose(self):
        if MasteryPanelInjectorView._g_controller:
            MasteryPanelInjectorView._g_controller._onInjectorDisposed()
        super(MasteryPanelInjectorView, self)._dispose()

    def py_onDragEnd(self, offset):
        if MasteryPanelInjectorView._g_controller:
            MasteryPanelInjectorView._g_controller._onDragEnd(offset)

    def py_onPanelReady(self):
        if MasteryPanelInjectorView._g_controller:
            MasteryPanelInjectorView._g_controller._onPanelReady()

    def py_onViewModeChanged(self, mode):
        if MasteryPanelInjectorView._g_controller:
            MasteryPanelInjectorView._g_controller._onViewModeChanged(mode)


def _registerFlash():
    g_entitiesFactories.addSettings(ViewSettings(
        _LINKAGE, MasteryPanelInjectorView, _SWF,
        WindowLayer.WINDOW, None, ScopeTemplates.GLOBAL_SCOPE
    ))


def _unregisterFlash():
    try:
        g_entitiesFactories.removeSettings(_LINKAGE)
    except Exception:
        pass


class MasteryController(object):

    def __init__(self):
        self._injectorView  = None
        self._panelReady    = False
        self._enabled       = False
        self._hangarVisible = False
        self._visibleByData = False
        self._modalOpen     = False
        self._scaleBound    = False
        self._position      = [100, 100]
        self._viewMode      = _DEFAULT_VIEW_MODE
        self._xpCache       = {}
        self._moeCache      = {}
        self._xpCacheTs     = {}
        self._moeCacheTs    = {}
        self._pendingXp     = set()
        self._pendingMoe    = set()
        self._markHistory   = {}
        self._lastKnownMark = {}
        self._saveRev       = 0
        self._saveCallbackId = None
        self._loadCache()

    def enable(self):
        if self._enabled:
            return
        self._enabled = True
        self._injectorView  = None
        self._panelReady    = False
        self._visibleByData = False
        MasteryPanelInjectorView._g_controller = self
        g_currentVehicle.onChanged += self._onVehicleChanged
        try:
            ServicesLocator.settingsCore.interfaceScale.onScaleChanged += self._onScaleChanged
            self._scaleBound = True
        except Exception:
            self._scaleBound = False
        lsm = getLobbyStateMachine()
        if lsm is not None:
            lsm.onVisibleRouteChanged += self._onVisibleRouteChanged
            try:
                self._hangarVisible = self._isHangarState(lsm.visibleRouteInfo.state)
            except Exception:
                self._hangarVisible = False
        else:
            self._hangarVisible = False
        if self._hangarVisible:
            self._injectFlash()
        logger.debug('enabled, hangarVisible=%s', self._hangarVisible)

    def disable(self):
        if not self._enabled:
            return
        self._enabled = False
        try:
            g_currentVehicle.onChanged -= self._onVehicleChanged
        except Exception:
            pass
        if self._scaleBound:
            try:
                ServicesLocator.settingsCore.interfaceScale.onScaleChanged -= self._onScaleChanged
            except Exception:
                pass
            self._scaleBound = False
        lsm = getLobbyStateMachine()
        if lsm:
            try:
                lsm.onVisibleRouteChanged -= self._onVisibleRouteChanged
            except Exception:
                pass
        MasteryPanelInjectorView._g_controller = None
        self._injectorView  = None
        self._panelReady    = False
        self._hangarVisible = False
        self._visibleByData = False
        self._modalOpen     = False
        logger.debug('disabled')

    def _onScaleChanged(self, scale):
        if self._panelReady and self._injectorView:
            try:
                self._injectorView.flashObject.as_setPosition(self._position)
            except Exception:
                logger.exception('as_setPosition on scale change failed')
        self._refresh()

    @staticmethod
    def _isHangarState(state):
        cls = _getDefaultHangarStateCls()
        if cls is None or state is None:
            return False
        lsm = getLobbyStateMachine()
        if lsm is None:
            return False
        try:
            return state == lsm.getStateByCls(cls)
        except Exception:
            return False

    def _onVisibleRouteChanged(self, routeInfo):
        self._hangarVisible = self._isHangarState(routeInfo.state)
        if self._hangarVisible and not self._panelReady and not self._injectorView:
            self._injectFlash()
        if self._hangarVisible:
            self._captureCurrentMarkSample()
        self._updateVisibility()

    def _updateVisibility(self):
        if not (self._panelReady and self._injectorView):
            return
        visible = bool(self._hangarVisible and self._visibleByData and not self._modalOpen)
        try:
            self._injectorView.flashObject.as_setVisible(visible)
        except Exception:
            logger.exception('as_setVisible failed')

    def _onModalChanged(self, isModalOpen):
        newState = bool(isModalOpen)
        if self._modalOpen == newState:
            return
        self._modalOpen = newState
        logger.debug('modal state -> %s', self._modalOpen)
        self._updateVisibility()

    def _onVehicleChanged(self):
        self._captureCurrentMarkSample(forceAppend=False)
        self._refresh()

    def _captureCurrentMarkSample(self, forceAppend=False):
        if not g_currentVehicle.isPresent():
            return
        vehicle = g_currentVehicle.item
        tankID = getattr(vehicle, 'intCD', None)
        if tankID is None:
            return
        mark = _readMarkPercent(vehicle)
        if mark is None:
            return
        history = self._markHistory.setdefault(tankID, [])
        last = history[-1] if history else None
        if forceAppend or last is None or abs(float(last) - float(mark)) > 0.0001:
            history.append(mark)
            if len(history) > _MAX_HISTORY:
                del history[:-_MAX_HISTORY]
        self._lastKnownMark[tankID] = mark

    def _onBattleProcessed(self, tankID, moe):
        try:
            value = float(moe)
        except (TypeError, ValueError):
            return
        history = self._markHistory.setdefault(tankID, [])
        last = history[-1] if history else None
        appended = False
        if last is None or abs(float(last) - value) > 0.0001:
            history.append(value)
            if len(history) > _MAX_HISTORY:
                del history[:-_MAX_HISTORY]
            appended = True
        self._lastKnownMark[tankID] = value
        self._scheduleSaveCache()
        logger.debug('battle: tankID=%s moe=%.2f appended=%s history=%d',
                     tankID, value, appended, len(history))
        if (self._enabled and self._panelReady
                and g_currentVehicle.isPresent()
                and getattr(g_currentVehicle.item, 'intCD', None) == tankID):
            self._refresh()

    def _injectFlash(self, attempt=0):
        if not self._enabled:
            return
        try:
            app = ServicesLocator.appLoader.getDefLobbyApp()
            if app and app.initialized:
                app.loadView(SFViewLoadParams(_LINKAGE))
                return
        except Exception:
            logger.exception('inject failed (attempt=%d)', attempt)
        if attempt < _INJECT_MAX_ATTEMPTS:
            BigWorld.callback(_INJECT_RETRY_DELAY, lambda: self._injectFlash(attempt + 1))

    def _onInjectorReady(self, view):
        self._injectorView = view
        logger.debug('injector ready')

    def _onInjectorDisposed(self):
        self._injectorView = None
        self._panelReady   = False

    def _onPanelReady(self):
        self._panelReady = True
        logger.debug('panel ready pos=%s mode=%s', self._position, self._viewMode)
        if self._injectorView:
            try:
                self._injectorView.flashObject.as_setLocalization({
                    'loading': _tr('loading', u'...'),
                    'noData':  _tr('noData',  u'N/A'),
                })
                self._injectorView.flashObject.as_setPosition(self._position)
                self._injectorView.flashObject.as_setViewMode(int(self._viewMode))
                self._injectorView.flashObject.as_setVisible(False)
            except Exception:
                logger.exception('panel init calls failed')
        self._refresh()

    def _onViewModeChanged(self, mode):
        try:
            self._viewMode = int(mode)
            self._scheduleSaveCache()
            logger.debug('view mode changed: %s', self._viewMode)
        except Exception:
            self._viewMode = _DEFAULT_VIEW_MODE

    _EMPTY_XP  = {'thirdClass': 0, 'secondClass': 0, 'firstClass': 0, 'aceTanker': 0}
    _EMPTY_MOE = {'p65': 0, 'p85': 0, 'p95': 0, 'p100': 0}

    def _loadCache(self):
        if not os.path.isdir(_CACHE_DIR):
            try:
                os.makedirs(_CACHE_DIR)
            except OSError:
                pass
        if not os.path.isfile(_CACHE_FILE):
            return
        try:
            with open(_CACHE_FILE, 'rb') as fh:
                raw = fh.read()
                cached, version = cPickle.loads(zlib.decompress(raw))
                if version == _CACHE_VERSION and isinstance(cached, dict):
                    self._xpCache    = cached.get('xp',    {}) or {}
                    self._moeCache   = cached.get('moe',   {}) or {}
                    self._xpCacheTs  = cached.get('xpTs',  {}) or {}
                    self._moeCacheTs = cached.get('moeTs', {}) or {}
                    pos = cached.get('position')
                    if isinstance(pos, (list, tuple)) and len(pos) >= 2:
                        try:
                            self._position = [int(pos[0]), int(pos[1])]
                        except (TypeError, ValueError):
                            pass
                    try:
                        self._viewMode = int(cached.get('viewMode', _DEFAULT_VIEW_MODE))
                    except (TypeError, ValueError):
                        self._viewMode = _DEFAULT_VIEW_MODE
                    self._markHistory   = cached.get('markHistory',   {}) or {}
                    self._lastKnownMark = cached.get('lastKnownMark', {}) or {}
                    logger.debug('cache loaded: %d xp, %d moe, mode=%s, pos=%s',
                                 len(self._xpCache), len(self._moeCache),
                                 self._viewMode, self._position)
                else:
                    logger.debug('cache: version mismatch (got %s, want %s), discarding',
                                 version, _CACHE_VERSION)
        except Exception:
            logger.exception('cache: failed to load')

    def _scheduleSaveCache(self):
        self._saveRev += 1
        rev = self._saveRev
        _cancelCallbackSafe(self._saveCallbackId)
        self._saveCallbackId = BigWorld.callback(_CACHE_SAVE_DEBOUNCE, lambda: self._saveCache(rev))

    def _saveCache(self, rev=None):
        self._saveCallbackId = None
        if rev is not None and rev != self._saveRev:
            return
        try:
            if not os.path.isdir(_CACHE_DIR):
                os.makedirs(_CACHE_DIR)
            payload = {
                'xp':            self._xpCache,
                'moe':           self._moeCache,
                'xpTs':          self._xpCacheTs,
                'moeTs':         self._moeCacheTs,
                'position':      list(self._position),
                'viewMode':      self._viewMode,
                'markHistory':   self._markHistory,
                'lastKnownMark': self._lastKnownMark,
            }
            raw = zlib.compress(cPickle.dumps((payload, _CACHE_VERSION), cPickle.HIGHEST_PROTOCOL), 1)
            with open(_CACHE_FILE, 'wb') as fh:
                fh.write(raw)
            logger.debug('cache saved: %d xp, %d moe, mode=%s',
                         len(self._xpCache), len(self._moeCache), self._viewMode)
        except Exception:
            logger.exception('cache: failed to save')

    def _isFresh(self, tankID, distribution):
        tsMap = self._xpCacheTs if distribution == 'xp' else self._moeCacheTs
        ts = tsMap.get(tankID, 0)
        try:
            return (time.time() - float(ts)) < _CACHE_TTL_SECONDS
        except (TypeError, ValueError):
            return False

    def _refresh(self):
        if not (self._panelReady and self._injectorView):
            return
        if not g_currentVehicle.isPresent():
            self._visibleByData = False
            self._updateVisibility()
            try:
                self._injectorView.flashObject.as_clearData()
            except Exception:
                pass
            return
        tankID = getattr(g_currentVehicle.item, 'intCD', None)
        if tankID is None:
            self._visibleByData = False
            self._updateVisibility()
            return
        self._visibleByData = True
        self._updateVisibility()

        xp  = self._xpCache.get(tankID)
        moe = self._moeCache.get(tankID)
        xpFresh  = xp  is not None and self._isFresh(tankID, 'xp')
        moeFresh = moe is not None and self._isFresh(tankID, 'damage')
        if xp is None and moe is None:
            try:
                self._injectorView.flashObject.as_setLoading()
            except Exception:
                pass
        if xp is not None:
            self._pushMastery(xp)
        if not xpFresh:
            self._requestDistribution(tankID, 'xp')
        if moe is not None:
            self._pushMoe(moe)
        if not moeFresh:
            self._requestDistribution(tankID, 'damage')
        self._pushHistory(tankID)

    def _pushMastery(self, xp):
        if not self._injectorView:
            return
        try:
            self._injectorView.flashObject.as_setMasteryData(
                int(xp.get('thirdClass')  or 0),
                int(xp.get('secondClass') or 0),
                int(xp.get('firstClass')  or 0),
                int(xp.get('aceTanker')   or 0),
            )
        except Exception:
            logger.exception('as_setMasteryData failed')

    def _pushMoe(self, moe):
        if not self._injectorView:
            return
        try:
            self._injectorView.flashObject.as_setMoeData(
                int(moe.get('p65')  or 0),
                int(moe.get('p85')  or 0),
                int(moe.get('p95')  or 0),
                int(moe.get('p100') or 0),
            )
        except Exception:
            logger.exception('as_setMoeData failed')

    def _pushHistory(self, tankID):
        if not self._injectorView:
            return
        values  = self._markHistory.get(tankID, [])[-_MAX_HISTORY:]
        current = self._lastKnownMark.get(tankID)
        try:
            self._injectorView.flashObject.as_setBattleHistory(
                values,
                float(current if current is not None else 0.0)
            )
        except Exception:
            logger.exception('as_setBattleHistory failed')

    def _requestDistribution(self, tankID, distribution, attempt=1):
        isXp    = (distribution == 'xp')
        pending = self._pendingXp if isXp else self._pendingMoe
        if attempt == 1:
            if tankID in pending:
                return
            pending.add(tankID)
        query = _XP_PERCENTILES_QUERY if isXp else _MOE_PERCENTILES_QUERY
        url   = _buildApiUrl(tankID, distribution, query)
        logger.debug('api request tankID=%s dist=%s attempt=%d url=%s',
                     tankID, distribution, attempt, url)
        try:
            BigWorld.fetchURL(
                url,
                lambda response, t=tankID, d=distribution, a=attempt: self._onApiResponse(t, d, response, a),
                None, _API_TIMEOUT, 'GET', None,
            )
        except Exception:
            logger.exception('fetchURL failed tankID=%s dist=%s attempt=%d',
                             tankID, distribution, attempt)
            self._handleApiFailure(tankID, distribution, attempt)

    def _retryRequest(self, tankID, distribution, attempt):
        if not self._enabled:
            pending = self._pendingXp if distribution == 'xp' else self._pendingMoe
            pending.discard(tankID)
            return
        self._requestDistribution(tankID, distribution, attempt)

    def _handleApiFailure(self, tankID, distribution, attempt):
        isXp    = (distribution == 'xp')
        pending = self._pendingXp if isXp else self._pendingMoe
        if attempt < _API_MAX_ATTEMPTS:
            delay = _API_RETRY_BASE_DELAY * (2 ** (attempt - 1))
            nextAttempt = attempt + 1
            logger.debug('api retry tankID=%s dist=%s in %.1fs (next attempt=%d)',
                         tankID, distribution, delay, nextAttempt)
            BigWorld.callback(delay, lambda: self._retryRequest(tankID, distribution, nextAttempt))
            return
        pending.discard(tankID)
        logger.debug('api: gave up tankID=%s dist=%s after %d attempts',
                     tankID, distribution, attempt)
        current = g_currentVehicle.item if g_currentVehicle.isPresent() else None
        isCurrent = current is not None and getattr(current, 'intCD', None) == tankID
        if isCurrent and self._xpCache.get(tankID) is None and self._moeCache.get(tankID) is None:
            empty = self._EMPTY_XP if isXp else self._EMPTY_MOE
            (self._pushMastery if isXp else self._pushMoe)(empty)

    def _onApiResponse(self, tankID, distribution, response, attempt=1):
        isXp    = (distribution == 'xp')
        mapping = _PERCENTILE_TO_KEY if isXp else _MOE_PERCENTILE_TO_KEY
        pending = self._pendingXp if isXp else self._pendingMoe
        parsed = None
        status = 0
        try:
            body = getattr(response, 'body', None)
            status = getattr(response, 'responseCode', 0)
            if body and status and status < 400:
                payload = json.loads(body)
                parsed = _parseApiResponse(payload, tankID, mapping)
        except Exception:
            logger.exception('api parse failed tankID=%s dist=%s attempt=%d',
                             tankID, distribution, attempt)
        if parsed is None:
            isTransient = (not status) or status >= 500 or status == 429
            if isTransient and attempt < _API_MAX_ATTEMPTS:
                self._handleApiFailure(tankID, distribution, attempt)
                return
            pending.discard(tankID)
            logger.debug('api: no data tankID=%s dist=%s status=%s', tankID, distribution, status)
            current = g_currentVehicle.item if g_currentVehicle.isPresent() else None
            isCurrent = current is not None and getattr(current, 'intCD', None) == tankID
            if isCurrent and self._xpCache.get(tankID) is None and self._moeCache.get(tankID) is None:
                empty = self._EMPTY_XP if isXp else self._EMPTY_MOE
                (self._pushMastery if isXp else self._pushMoe)(empty)
            return
        pending.discard(tankID)
        nowTs = int(time.time())
        if isXp:
            self._xpCache[tankID]   = parsed
            self._xpCacheTs[tankID] = nowTs
        else:
            self._moeCache[tankID]   = parsed
            self._moeCacheTs[tankID] = nowTs
        self._scheduleSaveCache()
        current = g_currentVehicle.item if g_currentVehicle.isPresent() else None
        isCurrent = current is not None and getattr(current, 'intCD', None) == tankID
        if isCurrent:
            (self._pushMastery if isXp else self._pushMoe)(parsed)

    def _onDragEnd(self, offset):
        try:
            self._position = [int(offset[0]), int(offset[1])]
            self._scheduleSaveCache()
            logger.debug('drag end pos=%s', self._position)
        except Exception:
            logger.exception('drag save failed')


class _BattleResultsCollector(object):

    _TICK_INTERVAL = 1.0
    _MAX_GATE_ATTEMPTS = 30
    _MAX_RESPONSE_ATTEMPTS = 30
    _MAX_DOSSIER_ATTEMPTS = 20
    _DOSSIER_FIRST_DELAY = 0.5
    _DOSSIER_RETRY_DELAY = 1.5

    def __init__(self, controller):
        self._controller = controller
        self._queue = deque()
        self._available = False
        self._terminated = False
        self._installed = False
        self._tickCallbackId = None
        self._dossierCallbackIds = {}

    def init(self):
        if self._installed:
            return
        if g_messengerEvents is None or SYS_MESSAGE_TYPE is None:
            logger.debug('battle-results: messenger API unavailable, collector disabled')
            return
        try:
            g_messengerEvents.serviceChannel.onChatMessageReceived += self._onServiceMessage
        except Exception:
            logger.exception('battle-results: serviceChannel hook failed')
            return
        try:
            g_playerEvents.onAccountBecomeNonPlayer += self._onBecomeNonPlayer
        except Exception:
            pass
        if g_eventBus is not None and GUICommonEvent is not None:
            try:
                g_eventBus.addListener(GUICommonEvent.LOBBY_VIEW_LOADED, self._onLobbyLoaded)
            except Exception:
                logger.exception('battle-results: LOBBY_VIEW_LOADED subscribe failed')
        self._installed = True
        self._terminated = False
        self._scheduleTick()
        logger.debug('battle-results: collector started')

    def fini(self):
        self._terminated = True
        _cancelCallbackSafe(self._tickCallbackId)
        self._tickCallbackId = None
        for cbid, _mark in list(self._dossierCallbackIds.values()):
            _cancelCallbackSafe(cbid)
        self._dossierCallbackIds.clear()
        if not self._installed:
            return
        try:
            g_messengerEvents.serviceChannel.onChatMessageReceived -= self._onServiceMessage
        except Exception:
            pass
        try:
            g_playerEvents.onAccountBecomeNonPlayer -= self._onBecomeNonPlayer
        except Exception:
            pass
        if g_eventBus is not None and GUICommonEvent is not None:
            try:
                g_eventBus.removeListener(GUICommonEvent.LOBBY_VIEW_LOADED, self._onLobbyLoaded)
            except Exception:
                pass
        self._queue.clear()
        self._installed = False
        self._available = False

    def _onLobbyLoaded(self, *_):
        self._available = True

    def _onBecomeNonPlayer(self, *_):
        self._available = False

    def _onServiceMessage(self, _client, message):
        try:
            if not self._isBattleResultMessage(message):
                return
            data = getattr(message, 'data', None) or {}
            try:
                arenaID = int(data.get('arenaUniqueID', 0) or 0)
            except (TypeError, ValueError):
                return
            if arenaID <= 0:
                return
            for queued in self._queue:
                if queued[0] == arenaID:
                    return
            self._queue.append((arenaID, 0))
            logger.debug('battle-results: arena %s queued', arenaID)
        except Exception:
            logger.exception('battle-results: onServiceMessage failed')

    @staticmethod
    def _isBattleResultMessage(message):
        messageType = getattr(message, 'type', None)
        if messageType is None or SYS_MESSAGE_TYPE is None:
            return False
        try:
            name = str(SYS_MESSAGE_TYPE[messageType])
        except (KeyError, TypeError, ValueError):
            return False
        return name == 'battleResults'

    def _scheduleTick(self):
        if self._terminated:
            return
        _cancelCallbackSafe(self._tickCallbackId)
        self._tickCallbackId = BigWorld.callback(self._TICK_INTERVAL, self._tick)

    def _tick(self):
        self._tickCallbackId = None
        if self._terminated:
            return
        try:
            if self._available and self._queue:
                arenaID, attempt = self._queue.popleft()
                self._processOne(arenaID, attempt)
        except Exception:
            logger.exception('battle-results: tick failed')
        self._scheduleTick()

    def _processOne(self, arenaID, attempt):
        try:
            player = BigWorld.player()
            if not isinstance(player, PlayerAccount):
                self._requeueOrDrop(arenaID, attempt, 'no PlayerAccount')
                return
            try:
                synced = ServicesLocator.itemsCache.isSynced()
            except Exception:
                synced = False
            if not synced:
                self._requeueOrDrop(arenaID, attempt, 'itemsCache not synced')
                return
            cache = getattr(player, 'battleResultsCache', None)
            if cache is None:
                logger.debug('battle-results: arena %s no battleResultsCache, drop', arenaID)
                return
            cache.get(arenaID, functools.partial(self._onResults, arenaID, attempt))
        except Exception:
            logger.exception('battle-results: processOne failed arena %s', arenaID)

    def _requeueOrDrop(self, arenaID, attempt, reason):
        if attempt < self._MAX_GATE_ATTEMPTS:
            self._queue.append((arenaID, attempt + 1))
            logger.debug('battle-results: gate wait (%s) arena %s (%d/%d)',
                         reason, arenaID, attempt + 1, self._MAX_GATE_ATTEMPTS)
        else:
            logger.debug('battle-results: dropping arena %s (gate %s exhausted)',
                         arenaID, reason)

    def _onResults(self, arenaID, attempt, responseCode, results=None):
        try:
            if responseCode is None or responseCode < 0:
                if attempt < self._MAX_RESPONSE_ATTEMPTS:
                    self._queue.append((arenaID, attempt + 1))
                    logger.debug('battle-results: arena %s retry rc=%s (%d/%d)',
                                 arenaID, responseCode, attempt + 1, self._MAX_RESPONSE_ATTEMPTS)
                else:
                    logger.debug('battle-results: arena %s gave up after %d attempts rc=%s',
                                 arenaID, attempt, responseCode)
                return
            if not results:
                logger.debug('battle-results: arena %s empty results rc=%s, drop',
                             arenaID, responseCode)
                return
            self._extractAndApply(arenaID, results)
        except Exception:
            logger.exception('battle-results: onResults failed arena %s', arenaID)

    def _extractAndApply(self, arenaID, results):
        if not isinstance(results, dict):
            return
        common = results.get('common', {}) or {}
        guiType = common.get('guiType', 0)
        allowed = []
        for attr in ('RANDOM', 'MAPBOX'):
            val = getattr(constants.ARENA_GUI_TYPE, attr, None)
            if val is not None:
                allowed.append(val)
        if allowed and guiType not in allowed:
            logger.debug('battle-results: arena %s skipped, guiType=%s not in %s',
                         arenaID, guiType, allowed)
            return

        accountDBID = self._getAccountDBID()
        if not accountDBID:
            logger.debug('battle-results: arena %s no accountDBID', arenaID)
            return

        vehicles = results.get('vehicles', {}) or {}
        tankID = None
        for _, vehicleInfo in vehicles.iteritems():
            if not vehicleInfo:
                continue
            entry = vehicleInfo[0] if isinstance(vehicleInfo, list) else vehicleInfo
            if not isinstance(entry, dict):
                continue
            try:
                if int(entry.get('accountDBID', 0) or 0) != accountDBID:
                    continue
            except (TypeError, ValueError):
                continue
            try:
                tankID = int(entry.get('typeCompDescr', 0) or 0)
            except (TypeError, ValueError):
                tankID = 0
            if tankID:
                break

        if not tankID:
            logger.debug('battle-results: arena %s player tank not found', arenaID)
            return
        self._scheduleDossierRead(tankID, attempt=0)

    @staticmethod
    def _getAccountDBID():
        try:
            player = BigWorld.player()
            dbid = int(getattr(player, 'databaseID', 0) or 0)
            if dbid:
                return dbid
        except Exception:
            pass
        return 0

    def _scheduleDossierRead(self, tankID, attempt):
        if self._terminated:
            return
        prev = self._dossierCallbackIds.pop(tankID, None)
        if prev is not None:
            _cancelCallbackSafe(prev[0])
        delay = self._DOSSIER_FIRST_DELAY if attempt == 0 else self._DOSSIER_RETRY_DELAY
        expectedMark = self._controller._lastKnownMark.get(tankID)
        cbid = BigWorld.callback(delay, lambda t=tankID, a=attempt: self._readDossier(t, a))
        self._dossierCallbackIds[tankID] = (cbid, expectedMark)

    def _readDossier(self, tankID, attempt):
        entry = self._dossierCallbackIds.pop(tankID, None)
        if self._terminated:
            return
        expectedPrev = entry[1] if entry else None
        moe = _readMarkForTankID(tankID)
        if moe is None:
            if attempt < self._MAX_DOSSIER_ATTEMPTS:
                self._scheduleDossierRead(tankID, attempt + 1)
            else:
                logger.debug('battle-results: dossier gave up tankID=%s', tankID)
            return
        if (expectedPrev is not None
                and abs(float(expectedPrev) - float(moe)) < 0.0001
                and attempt < self._MAX_DOSSIER_ATTEMPTS):
            logger.debug('battle-results: dossier unchanged tankID=%s (%.2f), retry %d',
                         tankID, moe, attempt + 1)
            self._scheduleDossierRead(tankID, attempt + 1)
            return
        try:
            self._controller._onBattleProcessed(tankID, moe)
        except Exception:
            logger.exception('battle-results: controller dispatch failed tankID=%s', tankID)


class _ModalWindowWatcher(object):

    _STATUS_LOADED_FALLBACK    = 2
    _STATUS_DESTROYED_FALLBACK = 4

    def __init__(self, controller):
        self._controller = controller
        self._activeIDs = set()
        self._installed = False
        self._wm = None
        self._modalLayers = None

    def init(self):
        if self._installed:
            return
        if dependency is None or IGuiLoader is None:
            logger.debug('modal-watcher: GuiLoader API unavailable, watcher disabled')
            return
        try:
            guiLoader = dependency.instance(IGuiLoader)
            self._wm = getattr(guiLoader, 'windowsManager', None)
        except Exception:
            logger.exception('modal-watcher: cannot get windowsManager')
            return
        if self._wm is None:
            logger.debug('modal-watcher: windowsManager is None')
            return
        evt = getattr(self._wm, 'onWindowStatusChanged', None)
        if evt is None:
            logger.debug('modal-watcher: onWindowStatusChanged unavailable')
            return
        try:
            evt += self._onWindowStatusChanged
        except Exception:
            logger.exception('modal-watcher: subscribe failed')
            return
        self._installed = True
        logger.debug('modal-watcher: started, modalLayers=%s', self._getModalLayers())

    def fini(self):
        if self._installed and self._wm is not None:
            try:
                self._wm.onWindowStatusChanged -= self._onWindowStatusChanged
            except Exception:
                pass
        self._activeIDs.clear()
        self._wm = None
        self._installed = False

    def _getModalLayers(self):
        if self._modalLayers is None:
            layers = set()
            for name in ('FULLSCREEN_WINDOW', 'TOP_WINDOW'):
                v = getattr(WindowLayer, name, None)
                if v is not None:
                    layers.add(v)
            if not layers:
                layers = {8, 10}
            self._modalLayers = layers
        return self._modalLayers

    @staticmethod
    def _statusEquals(status, namedAttr, fallback):
        if WindowStatus is not None:
            named = getattr(WindowStatus, namedAttr, None)
            if named is not None:
                return status == named
        return status == fallback

    def _isLoaded(self, status):
        return self._statusEquals(status, 'LOADED', self._STATUS_LOADED_FALLBACK)

    def _isDestroyed(self, status):
        return self._statusEquals(status, 'DESTROYED', self._STATUS_DESTROYED_FALLBACK)

    @staticmethod
    def _isOwnPanel(window):
        if window is None:
            return False
        for holder in (window, getattr(window, 'content', None)):
            if holder is None:
                continue
            try:
                viewKey = getattr(holder, 'viewKey', None)
            except Exception:
                viewKey = None
            if viewKey is None:
                continue
            alias = getattr(viewKey, 'alias', None) or getattr(viewKey, 'name', None)
            if alias == _LINKAGE:
                return True
        return False

    def _onWindowStatusChanged(self, uniqueID, newStatus):
        try:
            loaded = self._isLoaded(newStatus)
            destroyed = self._isDestroyed(newStatus)
            if not (loaded or destroyed):
                return
            if loaded:
                if uniqueID in self._activeIDs:
                    return
                if self._wm is None:
                    return
                window = None
                try:
                    window = self._wm.getWindow(uniqueID)
                except Exception:
                    return
                if window is None:
                    return
                if self._isOwnPanel(window):
                    logger.debug('modal-watcher: ignoring own injector uniqueID=%s', uniqueID)
                    return
                layer = getattr(window, 'layer', -1)
                if layer not in self._getModalLayers():
                    return
                wasEmpty = (len(self._activeIDs) == 0)
                self._activeIDs.add(uniqueID)
                logger.debug('modal-watcher: opened uniqueID=%s layer=%s count=%d',
                             uniqueID, layer, len(self._activeIDs))
                if wasEmpty:
                    self._dispatch(True)
            else:
                if uniqueID not in self._activeIDs:
                    return
                self._activeIDs.discard(uniqueID)
                logger.debug('modal-watcher: closed uniqueID=%s count=%d',
                             uniqueID, len(self._activeIDs))
                if not self._activeIDs:
                    self._dispatch(False)
        except Exception:
            logger.exception('modal-watcher: status handler failed')

    def _dispatch(self, isModalOpen):
        try:
            self._controller._onModalChanged(isModalOpen)
        except Exception:
            logger.exception('modal-watcher: controller dispatch failed')


class _Mod(object):

    def __init__(self):
        self._ctrl = MasteryController()
        self._results = _BattleResultsCollector(self._ctrl)
        self._modalWatcher = _ModalWindowWatcher(self._ctrl)

    def init(self):
        _loadLocalization()
        _registerFlash()
        g_playerEvents.onAccountShowGUI        += self._onAccountShowGUI
        g_playerEvents.onAvatarBecomePlayer    += self._onAvatarBecomePlayer
        g_playerEvents.onAccountBecomeNonPlayer += self._onAccountBecomeNonPlayer
        g_playerEvents.onDisconnected          += self._onDisconnected
        self._results.init()
        self._modalWatcher.init()
        if self._isAccount():
            self._ctrl.enable()
        logger.debug('initialized v%s', __version__)

    def fini(self):
        try:
            g_playerEvents.onAccountShowGUI        -= self._onAccountShowGUI
            g_playerEvents.onAvatarBecomePlayer    -= self._onAvatarBecomePlayer
            g_playerEvents.onAccountBecomeNonPlayer -= self._onAccountBecomeNonPlayer
            g_playerEvents.onDisconnected          -= self._onDisconnected
        except Exception:
            pass
        self._modalWatcher.fini()
        self._results.fini()
        self._ctrl.disable()
        _unregisterFlash()
        logger.debug('finalized')

    @staticmethod
    def _isAccount():
        return isinstance(BigWorld.player(), PlayerAccount)

    def _onAccountShowGUI(self, _=None):
        self._ctrl.enable()

    def _onAvatarBecomePlayer(self):
        self._ctrl.disable()

    def _onAccountBecomeNonPlayer(self):
        if not self._isAccount():
            self._ctrl.disable()

    def _onDisconnected(self):
        self._ctrl.disable()


_g_mod = _Mod()


def init():
    try:
        _g_mod.init()
    except Exception:
        logger.exception('init failed')


def fini():
    try:
        _g_mod.fini()
    except Exception:
        logger.exception('fini failed')
