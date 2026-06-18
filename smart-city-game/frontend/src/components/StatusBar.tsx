import { useState } from 'react'
import { Eye, Gauge, Pause, Play, Radio, RefreshCcw, ShieldCheck, Siren, TimerReset, Zap, Clock3, CircleDot } from 'lucide-react'
import { tickSimulation, togglePause, setAuto, stormMode, escalateOverdue, reactivateResources } from '../api/client'

export default function StatusBar({ state, mapLayer, onMapLayerChange }: { state: any; mapLayer: 'incidents' | 'confidence' | 'pressure'; onMapLayerChange: (layer: 'incidents' | 'confidence' | 'pressure') => void }) {
  const [working, setWorking] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)

  const simClock = state?.reloj?.simNow || state?.simNow || state?.simClock || state?.simulationTime || '-'
  const paused = state?.reloj?.paused ?? state?.paused ?? state?.simulationPaused ?? false
  const auto = state?.scheduler?.auto ?? state?.auto ?? state?.autoEnabled ?? false

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
      <span className="status-badge" title="Modo automático: la ciudad procesa ticks sin intervención manual" style={{
        background: auto ? 'rgba(56,189,248,0.1)' : 'rgba(74,85,104,0.2)',
        color: auto ? 'var(--accent-cyan)' : 'var(--hud-text-muted)',
        border: `1px solid ${auto ? 'rgba(56,189,248,0.25)' : 'rgba(74,85,104,0.3)'}`,
      }}>
        {auto ? 'Auto' : 'Manual'}
      </span>

      <div className="status-divider" />

      <div className="layer-toggle" title="Cambia la capa visual del mapa">
        <button className={`sim-btn ${mapLayer === 'incidents' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('incidents')} type="button" title="Ver zonas por cantidad de incidentes activos"><Eye size={12} /> Inc.</button>
        <button className={`sim-btn ${mapLayer === 'confidence' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('confidence')} type="button" title="Ver confianza promedio de sensores por zona"><ShieldCheck size={12} /> Conf.</button>
        <button className={`sim-btn ${mapLayer === 'pressure' ? 'sim-btn--primary' : ''}`} onClick={() => onMapLayerChange('pressure')} type="button" title="Ver presión operacional por zona"><Gauge size={12} /> Presión</button>
      </div>

      <div className="status-divider" />

      <button className="sim-btn" title="Procesa un ciclo de reglas: llegadas, finales, revisiones y automatizaciones" onClick={() => run('Tick', tickSimulation)} disabled={!!working}>
        <Zap size={12} />
        {working === 'Tick' ? '...' : 'Tick'}
      </button>
      <button className="sim-btn sim-btn--danger" title="Genera una ráfaga de 20 eventos para estresar la ciudad" onClick={() => run('Storm', () => stormMode(20))} disabled={!!working}>
        <Siren size={12} />
        {working === 'Storm' ? '...' : 'Storm 20'}
      </button>
      <button className="sim-btn" title="Fuerza la evaluación de incidentes vencidos y escalamiento" onClick={() => run('Escalar', escalateOverdue)} disabled={!!working}>
        <TimerReset size={12} />
        {working === 'Escalar' ? '...' : 'Escalar'}
      </button>
      <button className="sim-btn sim-btn--success" title="Reactiva recursos que ya cumplieron su ventana de inhabilitación" onClick={() => run('Reactivar', reactivateResources)} disabled={!!working}>
        <RefreshCcw size={12} />
        {working === 'Reactivar' ? '...' : 'Reactivar'}
      </button>
      <button className="sim-btn" title="Pausa o reanuda el reloj de simulación" onClick={() => run('Pausa', togglePause)} disabled={!!working}>
        {paused ? <Play size={12} /> : <Pause size={12} />}
        {working === 'Pausa' ? '...' : paused ? 'Play' : 'Pausa'}
      </button>
      <button className="sim-btn sim-btn--primary" title="Activa o desactiva el procesamiento automático de la ciudad" onClick={() => run('Auto', () => setAuto(!auto))} disabled={!!working}>
        <Radio size={12} />
        {working === 'Auto' ? '...' : auto ? 'Auto OFF' : 'Auto ON'}
      </button>

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
