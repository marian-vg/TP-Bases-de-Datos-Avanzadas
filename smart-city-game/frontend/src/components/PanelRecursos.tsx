import { useState } from 'react'
import { CircleDot, Ambulance, ShieldBan, Wrench } from 'lucide-react'
import { reactivateResources } from '../api/client'

export default function PanelRecursos({ state }: { state: any }) {
  const [working, setWorking] = useState(false)
  const [feedback, setFeedback] = useState<string | null>(null)

  const recursos = state?.recursos || []

  const byEstado = recursos.reduce((acc: any, r: any) => {
    const estado = String(r.estado || 'desconocido').toLowerCase()
    acc[estado] = (acc[estado] || 0) + 1
    return acc
  }, {})

  const disponibles = byEstado.disponible || 0
  const ocupados = (byEstado.ocupado || 0) + (byEstado['en tránsito'] || 0) + (byEstado['en transito'] || 0)
  const penalizados = byEstado['fuera de servicio'] || 0
  const mantenimiento = byEstado['en mantenimiento'] || 0

  const handleReactivate = async () => {
    setWorking(true)
    try {
      await reactivateResources()
      setFeedback('Reactivados')
    } catch (e) {
      setFeedback('Error: ' + (e as Error).message)
    } finally {
      setWorking(false)
      setTimeout(() => setFeedback(null), 3000)
    }
  }

  const rows = [
    { label: 'Disponibles', value: disponibles, icon: CircleDot, color: 'var(--accent-emerald)', bg: 'rgba(52,211,153,0.1)' },
    { label: 'Ocupados', value: ocupados, icon: Ambulance, color: 'var(--accent-amber)', bg: 'rgba(251,191,36,0.1)' },
    { label: 'Penalizados', value: penalizados, icon: ShieldBan, color: 'var(--accent-red)', bg: 'rgba(248,113,113,0.1)' },
    { label: 'Mantenimiento', value: mantenimiento, icon: Wrench, color: 'var(--hud-text-muted)', bg: 'rgba(74,85,104,0.15)' },
  ]

  return (
    <div style={{ padding: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 }}>
        {rows.map((row) => {
          const Icon = row.icon
          return (
            <div key={row.label} className="resource-stat">
              <div>
                <div className="resource-stat-label">{row.label}</div>
                <div className="resource-stat-value" style={{ color: row.color }}>{row.value}</div>
              </div>
              <div className="resource-stat-icon" style={{ background: row.bg, color: row.color }}>
                <Icon size={14} />
              </div>
            </div>
          )
        })}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <button
          className="sim-btn sim-btn--success"
          onClick={handleReactivate}
          disabled={working}
          style={{ fontSize: 10 }}
        >
          {working ? 'Reactivando...' : 'Reactivar vencidos'}
        </button>
        {feedback && (
          <span style={{ fontSize: 10, fontFamily: 'var(--font-mono)', color: 'var(--accent-cyan)' }}>{feedback}</span>
        )}
      </div>
    </div>
  )
}
