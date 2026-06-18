import { useState } from 'react'
import { closeIncident } from '../api/client'

function getGravityStyle(g: number) {
  if (g >= 5) return 'badge-severity badge-severity--critical'
  if (g >= 3) return 'badge-severity badge-severity--medium'
  return 'badge-severity badge-severity--low'
}

function selectedZoneName(state: any, selectedZoneId: number | null) {
  if (!selectedZoneId) return null
  return state?.zonas?.find((zona: any) => zona.id_zona === selectedZoneId)?.nombre || null
}

export default function PanelIncidentes({ state, selectedZoneId }: { state: any; selectedZoneId?: number | null }) {
  const [closing, setClosing] = useState<number | null>(null)
  const [error, setError] = useState<string | null>(null)

  const zona = selectedZoneName(state, selectedZoneId ?? null)
  const incidentes = (state?.incidentesActivos || []).filter((inc: any) => {
    if (!selectedZoneId) return true
    return inc.fk_zona_id === selectedZoneId || inc.zona_id === selectedZoneId || inc.zona === zona
  })

  const handleClose = async (id: number) => {
    setClosing(id)
    setError(null)
    try {
      await closeIncident(id)
    } catch (e) {
      setError('Error: ' + (e as Error).message)
    } finally {
      setClosing(null)
      setTimeout(() => setError(null), 3000)
    }
  }

  if (incidentes.length === 0) {
    return <div className="panel-empty">{selectedZoneId ? 'La zona no tiene incidentes activos' : 'Sin incidentes activos'}</div>
  }

  return (
    <div className="panel-list">
      {error && <div className="panel-error">{error}</div>}
      {incidentes.map((inc: any) => {
        const id = inc.id_incidente ?? inc.id
        const gravedad = Number(inc.gravedad_id ?? inc.gravedad ?? 0)
        return (
          <article key={id} className="incident-card">
            <div className="incident-card-topline">
              <span className="incident-id">#{id}</span>
              <span className={getGravityStyle(gravedad)}>{inc.gravedad || inc.gravedad_id || 'G'}</span>
            </div>
            <h3>{inc.tipo || inc.tipo_incidente || 'Incidente sin tipo'}</h3>
            <p>{inc.descripcion || 'La ciudad registró el evento y activó el circuito de respuesta.'}</p>
            <div className="incident-meta-grid">
              <span><strong>Zona</strong>{inc.zona || zona || '-'}</span>
              <span><strong>Minutos</strong>{inc.minutos_transcurridos || inc.minutosTranscurridos || 0}</span>
              <span><strong>Estado</strong>{inc.estado_actual || inc.estado || 'activo'}</span>
              <span><strong>Prioridad</strong>{inc.prioridad ?? '-'}</span>
            </div>
            <button className="action-btn incident-close" onClick={() => handleClose(id)} disabled={closing === id}>
              {closing === id ? 'Cerrando...' : 'Cerrar incidente'}
            </button>
          </article>
        )
      })}
    </div>
  )
}
