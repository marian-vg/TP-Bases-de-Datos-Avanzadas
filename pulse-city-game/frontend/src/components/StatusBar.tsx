import { useState } from 'react'
import { Pause, Play, Radio, RefreshCcw, Siren, TimerReset, Zap } from 'lucide-react'
import { tickSimulation, togglePause, setAuto, stormMode, escalateOverdue, reactivateResources } from '../api/client'

export default function StatusBar({ state }: { state: any }) {
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
      {/* Clock & status badges */}
      <span className="status-badge" style={{ background: 'rgba(56,189,248,0.08)', color: 'var(--accent-cyan)', border: '1px solid rgba(56,189,248,0.2)' }}>
        ⏱ {simClock}
      </span>
      <span className="status-badge" style={{
        background: paused ? 'rgba(251,191,36,0.1)' : 'rgba(52,211,153,0.1)',
        color: paused ? 'var(--accent-amber)' : 'var(--accent-emerald)',
        border: `1px solid ${paused ? 'rgba(251,191,36,0.25)' : 'rgba(52,211,153,0.25)'}`,
      }}>
        {paused ? '⏸ Pausado' : '▶ Activo'}
      </span>
      <span className="status-badge" style={{
        background: auto ? 'rgba(56,189,248,0.1)' : 'rgba(74,85,104,0.2)',
        color: auto ? 'var(--accent-cyan)' : 'var(--hud-text-muted)',
        border: `1px solid ${auto ? 'rgba(56,189,248,0.25)' : 'rgba(74,85,104,0.3)'}`,
      }}>
        {auto ? '⚡ Auto' : '○ Manual'}
      </span>

      <div style={{ width: 1, height: 16, background: 'var(--hud-border)', margin: '0 4px' }} />

      {/* Sim controls */}
      <button className="sim-btn" onClick={() => run('Tick', tickSimulation)} disabled={!!working}>
        <Zap size={12} />
        {working === 'Tick' ? '...' : 'Tick'}
      </button>
      <button className="sim-btn sim-btn--danger" onClick={() => run('Storm', () => stormMode(20))} disabled={!!working}>
        <Siren size={12} />
        {working === 'Storm' ? '...' : 'Storm 20'}
      </button>
      <button className="sim-btn" onClick={() => run('Escalar', escalateOverdue)} disabled={!!working}>
        <TimerReset size={12} />
        {working === 'Escalar' ? '...' : 'Escalar'}
      </button>
      <button className="sim-btn sim-btn--success" onClick={() => run('Reactivar', reactivateResources)} disabled={!!working}>
        <RefreshCcw size={12} />
        {working === 'Reactivar' ? '...' : 'Reactivar'}
      </button>
      <button className="sim-btn" onClick={() => run('Pausa', togglePause)} disabled={!!working}>
        {paused ? <Play size={12} /> : <Pause size={12} />}
        {working === 'Pausa' ? '...' : paused ? 'Play' : 'Pausa'}
      </button>
      <button className="sim-btn sim-btn--primary" onClick={() => run('Auto', () => setAuto(!auto))} disabled={!!working}>
        <Radio size={12} />
        {working === 'Auto' ? '...' : auto ? 'Auto OFF' : 'Auto ON'}
      </button>

      {feedback && (
        <>
          <div style={{ width: 1, height: 16, background: 'var(--hud-border)', margin: '0 4px' }} />
          <span className="status-badge" style={{ background: 'rgba(56,189,248,0.08)', color: 'var(--accent-cyan)', border: '1px solid rgba(56,189,248,0.2)' }}>
            {feedback}
          </span>
        </>
      )}
    </div>
  )
}
