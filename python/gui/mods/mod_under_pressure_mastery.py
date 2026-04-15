# -*- coding: utf-8 -*-
import cPickle
import json
import logging
import os
import zlib

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

logger = logging.getLogger('under_pressure.mastery')
logger.setLevel(logging.DEBUG if os.path.isfile('.debug_mods') else logging.ERROR)

__version__ = '0.0.1'

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

try:
    _prefsFilePath = BigWorld.wg_getPreferencesFilePath()
except AttributeError:
    _prefsFilePath = BigWorld.getPreferencesFilePath()

_CACHE_DIR = os.path.normpath(os.path.join(os.path.dirname(_prefsFilePath), 'mods', 'mastery'))
_CACHE_FILE = os.path.join(_CACHE_DIR, 'cache.dat')
_CACHE_VERSION = 1
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
    record = _findTankRecord(payload.get('data'), tankID)
    if not isinstance(record, dict):
        return None
    result = {}
    for percentile, key in mapping:
        result[key] = _extractPercentile(record, percentile)
    if all(v is None for v in result.itervalues()):
        return None
    return result


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
        self._injectorView = None
        self._panelReady = False
        self._enabled = False
        self._hangarVisible = False
        self._visibleByData = False
        self._scaleBound = False
        self._position = [100, 100]
        self._xpCache = {}
        self._moeCache = {}
        self._pendingXp = set()
        self._pendingMoe = set()
        self._saveRev = 0
        self._saveCallbackId = None
        self._loadCache()

    def enable(self):
        if self._enabled:
            return
        self._enabled = True
        self._injectorView = None
        self._panelReady = False
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
        self._injectorView = None
        self._panelReady = False
        self._hangarVisible = False
        self._visibleByData = False
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
        self._updateVisibility()

    def _updateVisibility(self):
        if not (self._panelReady and self._injectorView):
            return
        visible = bool(self._hangarVisible and self._visibleByData)
        try:
            self._injectorView.flashObject.as_setVisible(visible)
        except Exception:
            logger.exception('as_setVisible failed')

    def _onVehicleChanged(self):
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
        self._panelReady = False

    def _onPanelReady(self):
        self._panelReady = True
        logger.debug('panel ready pos=%s', self._position)
        if self._injectorView:
            try:
                self._injectorView.flashObject.as_setLocalization({
                    'loading': _tr('loading', u'...'),
                    'noData':  _tr('noData',  u'N/A'),
                })
                self._injectorView.flashObject.as_setPosition(self._position)
                self._injectorView.flashObject.as_setVisible(self._hangarVisible)
            except Exception:
                logger.exception('panel init calls failed')
        self._refresh()

    _EMPTY_XP = {'thirdClass': 0, 'secondClass': 0, 'firstClass': 0, 'aceTanker': 0}
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
                    self._xpCache = cached.get('xp', {}) or {}
                    self._moeCache = cached.get('moe', {}) or {}
                    pos = cached.get('position')
                    if isinstance(pos, (list, tuple)) and len(pos) >= 2:
                        try:
                            self._position = [int(pos[0]), int(pos[1])]
                        except (TypeError, ValueError):
                            pass
                    logger.debug('cache loaded: %d xp, %d moe records, pos=%s',
                                 len(self._xpCache), len(self._moeCache),
                                 self._position)
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
                'xp': self._xpCache,
                'moe': self._moeCache,
                'position': list(self._position),
            }
            raw = zlib.compress(cPickle.dumps((payload, _CACHE_VERSION), cPickle.HIGHEST_PROTOCOL), 1)
            with open(_CACHE_FILE, 'wb') as fh:
                fh.write(raw)
            logger.debug('cache saved: %d xp, %d moe records',
                         len(self._xpCache), len(self._moeCache))
        except Exception:
            logger.exception('cache: failed to save')

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

        xp = self._xpCache.get(tankID)
        moe = self._moeCache.get(tankID)
        if xp is None and moe is None:
            try:
                self._injectorView.flashObject.as_setLoading()
            except Exception:
                pass
        if xp is not None:
            self._pushMastery(xp)
        else:
            self._requestDistribution(tankID, 'xp')
        if moe is not None:
            self._pushMoe(moe)
        else:
            self._requestDistribution(tankID, 'damage')

    def _pushMastery(self, xp):
        if not self._injectorView:
            return
        try:
            self._injectorView.flashObject.as_setMasteryData(
                int(xp.get('thirdClass') or 0),
                int(xp.get('secondClass') or 0),
                int(xp.get('firstClass') or 0),
                int(xp.get('aceTanker') or 0),
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

    def _requestDistribution(self, tankID, distribution):
        isXp = (distribution == 'xp')
        pending = self._pendingXp if isXp else self._pendingMoe
        if tankID in pending:
            return
        pending.add(tankID)
        query = _XP_PERCENTILES_QUERY if isXp else _MOE_PERCENTILES_QUERY
        url = _buildApiUrl(tankID, distribution, query)
        logger.debug('api request tankID=%s dist=%s url=%s', tankID, distribution, url)
        try:
            BigWorld.fetchURL(
                url,
                lambda response, t=tankID, d=distribution: self._onApiResponse(t, d, response),
                None, _API_TIMEOUT, 'GET', None,
            )
        except Exception:
            logger.exception('fetchURL failed tankID=%s dist=%s', tankID, distribution)
            pending.discard(tankID)
            if isXp:
                self._pushMastery(self._EMPTY_XP)
            else:
                self._pushMoe(self._EMPTY_MOE)

    def _onApiResponse(self, tankID, distribution, response):
        isXp = (distribution == 'xp')
        mapping = _PERCENTILE_TO_KEY if isXp else _MOE_PERCENTILE_TO_KEY
        pending = self._pendingXp if isXp else self._pendingMoe
        pending.discard(tankID)
        parsed = None
        try:
            body = getattr(response, 'body', None)
            status = getattr(response, 'responseCode', 0)
            if body and status and status < 400:
                payload = json.loads(body)
                parsed = _parseApiResponse(payload, tankID, mapping)
        except Exception:
            logger.exception('api parse failed tankID=%s dist=%s', tankID, distribution)
        current = g_currentVehicle.item if g_currentVehicle.isPresent() else None
        isCurrent = current is not None and getattr(current, 'intCD', None) == tankID
        if parsed is None:
            logger.debug('api: no data tankID=%s dist=%s', tankID, distribution)
            if isCurrent:
                empty = self._EMPTY_XP if isXp else self._EMPTY_MOE
                (self._pushMastery if isXp else self._pushMoe)(empty)
            return
        if isXp:
            self._xpCache[tankID] = parsed
        else:
            self._moeCache[tankID] = parsed
        self._scheduleSaveCache()
        if isCurrent:
            (self._pushMastery if isXp else self._pushMoe)(parsed)

    def _onDragEnd(self, offset):
        try:
            self._position = [int(offset[0]), int(offset[1])]
            self._scheduleSaveCache()
            logger.debug('drag end pos=%s', self._position)
        except Exception:
            logger.exception('drag save failed')

class _Mod(object):

    def __init__(self):
        self._ctrl = MasteryController()

    def init(self):
        _loadLocalization()
        _registerFlash()
        g_playerEvents.onAccountShowGUI += self._onAccountShowGUI
        g_playerEvents.onAvatarBecomePlayer += self._onAvatarBecomePlayer
        g_playerEvents.onAccountBecomeNonPlayer += self._onAccountBecomeNonPlayer
        g_playerEvents.onDisconnected += self._onDisconnected
        if self._isAccount():
            self._ctrl.enable()
        logger.debug('initialized v%s', __version__)

    def fini(self):
        try:
            g_playerEvents.onAccountShowGUI -= self._onAccountShowGUI
            g_playerEvents.onAvatarBecomePlayer -= self._onAvatarBecomePlayer
            g_playerEvents.onAccountBecomeNonPlayer -= self._onAccountBecomeNonPlayer
            g_playerEvents.onDisconnected -= self._onDisconnected
        except Exception:
            pass
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
