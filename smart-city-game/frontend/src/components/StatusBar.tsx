import { useState, useRef, useEffect } from 'react'
import { Eye, Gauge, Pause, Play, Radio, RefreshCcw, ShieldCheck, Siren, TimerReset, Zap, Clock3, CircleDot, ChevronDown, Settings } from 'lucide-react'
import { tickSimulation, togglePause, setAuto, stormMode, escalateOverdue, reactivateResources } from '../api/client'

export default function StatusBar({ state, mapLayer, onMapLayerChange }: { state: any; mapLayer: 'incidents' | 'confidence' | 'pressure'; onMapLayerChange: (layer: 'incidents' | 'confidence' | 'pressure') => void }) {
  const [working, setWorking] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  const simClock = state?.reloj?.simNow || state?.simNow || state?.simClock || state?.simulationTime || '-'
  const paused = state?.reloj?.paused ?? state?.paused ?? state?.simulationPaused ?? false
  const auto = state?.scheduler?.auto ?? state?.auto ?? state?.autoEnabled ?? false

  // Cerrar al hacer click afuera
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setMenuOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const run = async (label: string, fn: () => Promise<any>) => {
    setWorking(label)
    setFeedback(null)
    try {
      await fn()
      setFeedback(label + ' ok')
    } catch (e) {
      setFeedback(label + ' fallo: ' + (e as Error).message)
    } finally {
      setWorking(null)
      setTimeout(() => setFeedback(null), 2500)
    }
  }

  return (
    <div className="status-bar">
      <span className="status-badge" title="Reloj simulado que gobierna los procesos del juego" style={{ background: 'rgba(56,189,248,0.08)', color: 'var(--accent-cyan)', border: '1px solid rgba(56,189,248,0.2)' }}>
        <Clock3 size={11} /> {simClock}
      </span>
      <span className="status-badge" title="Estado del scheduler de simulación" style={{
        background: paused ? 'rgba(251,191,36,0.1)' : 'rgba(52,211,153,0.1)',
        color: paused ? 'var(--accent-amber)' : 'var(--accent-emerald)',
        border: `1px solid ${paused ? 'rgba(251,191,36,0.25)' : 'rgba(52,211,153,0.25)'}`,
      }}>
        <CircleDot size={10} /> {paused ? 'Pausado' : 'Activo'}
      </span>
      <span className="status-badge" title="Inyección automática: la simulación inyecta catástrofes aleatorias de forma autónoma" style={{
        background: auto ? 'rgba(56,189,248,0.1)' : 'rgba(74,85,104,0.2)',
        color: auto ? 'var(--accent-cyan)' : 'var(--hud-text-muted)',
        border: `1px solid ${auto ? 'rgba(56,189,248,0.25)' : 'rgba(74,85,104,0.3)'}`,
      }}>
        {auto ? 'Inyección Auto: ON' : 'Inyección Auto: OFF'}
      </span>

      <div className="status-divider" />

      <div className="layer-toggle" title="Cambia la capa visual del mapa">
        <button className={`sim-btn ${mapLayer === 'incidents' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('incidents')} type="button" title="Ver zonas por cantidad de incidentes activos"><Eye size={12} /> Inc.</button>
        <button className={`sim-btn ${mapLayer === 'confidence' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('confidence')} type="button" title="Ver confianza promedio de sensores por zona"><ShieldCheck size={12} /> Conf.</button>
        <button className={`sim-btn ${mapLayer === 'pressure' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('pressure')} type="button" title="Ver presión operacional por zona"><Gauge size={12} /> Presión</button>
      </div>

      <div className="status-divider" />

      {/* Menú Dropdown de Controles de Simulación */}
      <div className="sim-menu-container" ref={menuRef}>
        <button
          className={`sim-btn sim-btn--primary sim-menu-trigger ${menuOpen ? 'active' : ''}`}
          onClick={() => setMenuOpen(!menuOpen)}
          type="button"
        >
          <Settings size={12} />
          <span>Controles de Simulación</span>
          <ChevronDown size={10} className={`chevron ${menuOpen ? 'open' : ''}`} />
        </button>

        {menuOpen && (
          <div className="sim-dropdown-menu">
            {/* Play / Pausa */}
            <button
              type="button"
              className="sim-dropdown-item"
              onClick={() => { run('Pausa', togglePause); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon">{paused ? <Play size={13} /> : <Pause size={13} />}</div>
              <div className="item-details">
                <div className="item-title">{paused ? 'Reanudar Reloj (Play)' : 'Pausar Reloj (Pausa)'}</div>
                <div className="item-desc">Detiene o reanuda el avance del tiempo simulado de la ciudad.</div>
              </div>
            </button>

            {/* Activar/Desactivar Inyección Auto */}
            <button
              type="button"
              className="sim-dropdown-item"
              onClick={() => { run('Auto', () => setAuto(!auto)); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon"><Radio size={13} /></div>
              <div className="item-details">
                <div className="item-title">{auto ? 'Desactivar Inyección Auto' : 'Activar Inyección Auto'}</div>
                <div className="item-desc">El sistema inyecta catástrofes aleatorias automáticamente cada 15s.</div>
              </div>
            </button>

            <div className="sim-dropdown-divider" />

            {/* Tick */}
            <button
              type="button"
              className="sim-dropdown-item"
              onClick={() => { run('Tick', tickSimulation); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon"><Zap size={13} /></div>
              <div className="item-details">
                <div className="item-title">Procesar Tick (Simular Paso)</div>
                <div className="item-desc">Fuerza el procesamiento de un ciclo manual (viajes, arribos y revisiones).</div>
              </div>
            </button>

            {/* Storm 20 */}
            <button
              type="button"
              className="sim-dropdown-item sim-dropdown-item--danger"
              onClick={() => { run('Storm', () => stormMode(20)); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon"><Siren size={13} /></div>
              <div className="item-details">
                <div className="item-title">Inyectar Tormenta (Storm 20)</div>
                <div className="item-desc">Provoca una ráfaga masiva de 20 catástrofes para estresar la red.</div>
              </div>
            </button>

            {/* Escalar */}
            <button
              type="button"
              className="sim-dropdown-item"
              onClick={() => { run('Escalar', escalateOverdue); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon"><TimerReset size={13} /></div>
              <div className="item-details">
                <div className="item-title">Forzar Escalamiento de SLA</div>
                <div className="item-desc">Ejecuta sp_EscalarIncidente: sube la gravedad si superó el tiempo límite.</div>
              </div>
            </button>

            {/* Reactivar */}
            <button
              type="button"
              className="sim-dropdown-item sim-dropdown-item--success"
              onClick={() => { run('Reactivar', reactivateResources); setMenuOpen(false); }}
              disabled={!!working}
            >
              <div className="item-icon"><RefreshCcw size={13} /></div>
              <div className="item-details">
                <div className="item-title">Reactivar Recursos (sp_Reactivar)</div>
                <div className="item-desc">Habilita los recursos suspendidos temporalmente por acumular penalizaciones.</div>
              </div>
            </button>
          </div>
        )}
      </div>

      {feedback && (
        <>
          <div className="status-divider" />
          <span className="status-badge" style={{ background: 'rgba(56,189,248,0.08)', color: 'var(--accent-cyan)', border: '1px solid rgba(56,189,248,0.2)' }}>
            {feedback}
          </span>
        </>
      )}
    </div>
  )
}
