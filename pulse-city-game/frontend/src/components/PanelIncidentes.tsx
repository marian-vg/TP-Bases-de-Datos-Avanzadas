import { useState } from 'react'
import { closeIncident } from '../api/client'

function getGravityStyle(g: number) {
  if (g >= 5) return 'badge-severity badge-severity--critical'
  if (g >= 3) return 'badge-severity badge-severity--medium'
  return 'badge-severity badge-severity--low'
}

export default function PanelIncidentes({ state }: { state: any }) {
  const [closing, setClosing] = useState<number | null>(null)
  const [error, setError] = useState<string | null>(null)

  const incidentes = state?.incidentesActivos || []

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
    return <div className="panel-empty">Sin incidentes activos</div>
  }

  return (
    <div style={{ padding: '4px 0' }}>
      {error && (
        <div style={{ margin: '4px 8px', padding: '4px 8px', borderRadius: 4, fontSize: 10, background: 'rgba(248,113,113,0.08)', border: '1px solid rgba(248,113,113,0.2)', color: 'var(--accent-red)' }}>
          {error}
        </div>
      )}
      <table className="hud-table">
        <thead>
          <tr>
            <th>ID</th>
            <th>Tipo</th>
            <th>G</th>
            <th>Zona</th>
            <th>Min</th>
            <th>Estado</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {incidentes.map((inc: any) => (
            <tr key={inc.id_incidente ?? inc.id}>
              <td style={{ fontFamily: 'var(--font-mono)', fontWeight: 600 }}>#{inc.id_incidente ?? inc.id}</td>
              <td>{inc.tipo || inc.tipo_incidente || '-'}</td>
              <td>
                <span className={getGravityStyle(Number(inc.gravedad_id ?? inc.gravedad ?? 0))}>
                  {inc.gravedad || inc.gravedad_id || '-'}
                </span>
              </td>
              <td>{inc.zona || '-'}</td>
              <td style={{ fontFamily: 'var(--font-mono)' }}>{inc.minutos_transcurridos || inc.minutosTranscurridos || 0}</td>
              <td>
                <span className="badge-status">
                  {inc.estado_actual || inc.estado || 'activo'}
                </span>
              </td>
              <td style={{ textAlign: 'right' }}>
                <button
                  className="action-btn"
                  onClick={() => handleClose(inc.id_incidente ?? inc.id)}
                  disabled={closing === (inc.id_incidente ?? inc.id)}
                >
                  {closing === (inc.id_incidente ?? inc.id) ? '...' : 'Cerrar'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
