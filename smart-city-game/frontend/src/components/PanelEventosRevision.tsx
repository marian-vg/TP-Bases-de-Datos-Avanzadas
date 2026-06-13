import { Hourglass } from 'lucide-react'

export default function PanelEventosRevision({ state }: { state: any }) {
  const eventos = state?.eventosEnRevision || []

  if (eventos.length === 0) {
    return <div className="panel-empty">Sin señales pendientes</div>
  }

  return (
    <div style={{ padding: '4px 6px', display: 'flex', flexDirection: 'column', gap: 4 }}>
      {eventos.map((evento: any) => (
        <div key={evento.evento_id} className="review-item">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              width: 28, height: 28, borderRadius: 4,
              background: 'rgba(251,191,36,0.1)',
              border: '1px solid rgba(251,191,36,0.2)',
              display: 'grid', placeItems: 'center',
              color: 'var(--accent-amber)',
            }}>
              <Hourglass size={13} />
            </div>
            <div>
              <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--hud-text)' }}>
                Evento #{evento.evento_id}
              </div>
              <div style={{ fontSize: 10, color: 'var(--hud-text-muted)' }}>
                Esperando confirmación operativa
              </div>
            </div>
          </div>
          <span style={{
            fontFamily: 'var(--font-mono)', fontSize: 11, fontWeight: 700,
            color: 'var(--accent-amber)',
            padding: '2px 6px', borderRadius: 3,
            background: 'rgba(251,191,36,0.08)',
            border: '1px solid rgba(251,191,36,0.2)',
          }}>
            {evento.seconds_remaining}s
          </span>
        </div>
      ))}
    </div>
  )
}
