import { Hourglass, RadioTower } from 'lucide-react'

function selectedZoneName(state: any, selectedZoneId: number | null) {
  if (!selectedZoneId) return null
  return state?.zonas?.find((zona: any) => zona.id_zona === selectedZoneId)?.nombre || null
}

export default function PanelEventosRevision({ state, selectedZoneId }: { state: any; selectedZoneId?: number | null }) {
  const zona = selectedZoneName(state, selectedZoneId ?? null)
  const eventos = (state?.eventosEnRevision || []).filter((evento: any) => {
    if (!selectedZoneId) return true
    return evento.zona_id === selectedZoneId || evento.zona === zona
  })

  if (eventos.length === 0) {
    return <div className="panel-empty">{selectedZoneId ? 'Sin revisión pendiente en esta zona' : 'Sin señales pendientes'}</div>
  }

  return (
    <div className="panel-list">
      {eventos.map((evento: any) => {
        const confidence = Math.round(Number(evento.confianza ?? evento.sensor_confianza ?? 0))
        const totalDelay = Number(evento.delay_seconds || 25)
        const remaining = Number(evento.seconds_remaining || 0)
        const progress = Math.max(0, Math.min(100, ((totalDelay - remaining) / Math.max(1, totalDelay)) * 100))
        const key = evento.review_key || evento.evento_id || `review-${Math.random()}`
        return (
          <article key={key} className="review-card">
            <div className="review-card-main">
              <div className="review-icon"><Hourglass size={15} /></div>
              <div>
                <div className="review-title">
                  {evento.evento_id ? `Evento #${evento.evento_id}` : 'Reporte Manual (Llamado)'}
                </div>
                <div className="review-subtitle">
                  {evento.tipo_evento || 'Llamado de emergencia'} en {evento.zona || zona || 'zona desconocida'}
                </div>
              </div>
            </div>
            <div className="review-sensor-line">
              <RadioTower size={12} /> {evento.sensor || evento.sensor_nombre || 'Reporte telefónico'} 
              {evento.evento_id ? ` · confianza ${confidence}%` : ' · Sin sensor compatible'}
            </div>
            <div className="review-progress"><span style={{ width: `${progress}%` }} /></div>
            <div className="review-footer"><span>Operador verificando veracidad</span><strong>{remaining}s</strong></div>
          </article>
        )
      })}
    </div>
  )
}
