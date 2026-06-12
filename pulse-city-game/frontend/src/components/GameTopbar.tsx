import { CircuitBoard, AlertTriangle, Ambulance, Hourglass, Database, Activity } from 'lucide-react'

interface GameTopbarProps {
  state: any
}

export default function GameTopbar({ state }: GameTopbarProps) {
  const incidentes = state?.incidentesActivos?.length ?? 0
  const recursos = state?.recursos?.length ?? 0
  const revision = state?.eventosEnRevision?.length ?? 0
  const penalizaciones = state?.penalizaciones?.length ?? 0
  const dbStatus = state?.dbStatus ?? 'OK'
  const score = state?.score ?? state?.puntaje ?? 0

  const zonas = state?.zonas || []
  const riesgoCount = { bajo: 0, moderado: 0, alto: 0, critico: 0 }
  zonas.forEach((z: any) => {
    const r = (z.nivel_riesgo || 'Bajo').toLowerCase()
    if (r in riesgoCount) riesgoCount[r as keyof typeof riesgoCount]++
  })

  return (
    <header className="game-topbar">
      <div className="brand-logo">
        <div className="brand-icon">
          <CircuitBoard size={16} />
        </div>
        <span className="brand-title">Pulse City</span>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flex: 1, flexWrap: 'wrap' }}>
        <div className="metric-chip">
          <AlertTriangle size={12} style={{ color: 'var(--accent-amber)' }} />
          <span className="metric-label">Incidentes</span>
          <span className="metric-value">{incidentes}</span>
        </div>

        <div className="metric-chip">
          <Ambulance size={12} style={{ color: 'var(--accent-emerald)' }} />
          <span className="metric-label">Recursos</span>
          <span className="metric-value">{recursos}</span>
        </div>

        <div className="metric-chip">
          <Hourglass size={12} style={{ color: 'var(--accent-amber)' }} />
          <span className="metric-label">Revisión</span>
          <span className="metric-value">{revision}</span>
        </div>

        <div className="metric-chip">
          <Activity size={12} style={{ color: 'var(--accent-red)' }} />
          <span className="metric-label">Penaliz.</span>
          <span className="metric-value">{penalizaciones}</span>
        </div>

        <div style={{ display: 'flex', gap: 4, marginLeft: 4 }}>
          <span className="legend-item">
            <span className="legend-dot" style={{ background: 'var(--risk-low)' }} />
            {riesgoCount.bajo}
          </span>
          <span className="legend-item">
            <span className="legend-dot" style={{ background: 'var(--risk-moderate)' }} />
            {riesgoCount.moderado}
          </span>
          <span className="legend-item">
            <span className="legend-dot" style={{ background: 'var(--risk-high)' }} />
            {riesgoCount.alto}
          </span>
          <span className="legend-item">
            <span className="legend-dot" style={{ background: 'var(--risk-critical)' }} />
            {riesgoCount.critico}
          </span>
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginLeft: 'auto' }}>
        <div className="metric-chip">
          <span className="metric-label">Puntaje</span>
          <span className="metric-value" style={{ color: 'var(--accent-emerald)' }}>{score}</span>
        </div>
        <div className="metric-chip">
          <Database size={11} style={{ color: dbStatus === 'OK' ? 'var(--accent-emerald)' : 'var(--accent-red)' }} />
          <span className="metric-value" style={{ color: dbStatus === 'OK' ? 'var(--accent-emerald)' : 'var(--accent-red)', fontSize: 10 }}>
            {dbStatus}
          </span>
        </div>
      </div>
    </header>
  )
}
