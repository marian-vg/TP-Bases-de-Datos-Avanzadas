import { useEffect, useState } from 'react'
import { fetchView } from '../api/client'

const VIEWS = [
  { value: 'vincidentesactivos', label: 'Incidentes Activos' },
  { value: 'vrecursosdisponibles', label: 'Recursos Disponibles' },
  { value: 'vrecursosocupados', label: 'Recursos Ocupados' },
  { value: 'vincidentescriticos', label: 'Incidentes Críticos' },
  { value: 'vhistorialincidentes', label: 'Historial Incidentes' },
  { value: 'vrecursospenalizados', label: 'Recursos Penalizados' },
  { value: 'vrecursoscandidatos', label: 'Recursos Candidatos' },
  { value: 'vhistorialasignaciones', label: 'Historial Asignaciones' },
  { value: 'vhistorialtriggers', label: 'Historial Triggers' },
  { value: 'vzonasincidentadas', label: 'Zonas Incidentadas' },
]

export default function PanelVistas() {
  const [selected, setSelected] = useState<string>('vincidentesactivos')
  const [reloadNonce, setReloadNonce] = useState(0)
  const [rows, setRows] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const loadInitialView = async () => {
      const view = selected
      setLoading(true)
      setError(null)
      try {
        const data = await fetchView(view)
        setRows(data || [])
      } catch (err) {
        setError((err as Error).message)
        setRows([])
      } finally {
        setLoading(false)
      }
    }

    void loadInitialView()
  }, [selected, reloadNonce])

  const columns = rows.length > 0 ? Object.keys(rows[0]) : []

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '4px 0' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, padding: '0 4px 6px 4px', borderBottom: '1px solid var(--hud-border)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontSize: 10, fontWeight: 700, color: 'var(--hud-text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
            Vista:
          </span>
          <select
            className="hud-select"
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
          >
            {VIEWS.map((v) => (
              <option key={v.value} value={v.value}>
                {v.label}
              </option>
            ))}
          </select>
        </div>
        <button
          className="sim-btn"
          onClick={() => setReloadNonce((current) => current + 1)}
          disabled={loading}
          style={{ fontSize: 10 }}
        >
          {loading ? 'Cargando...' : 'Recargar'}
        </button>
      </div>

      {error && (
        <div style={{ margin: '4px 8px', padding: '4px 8px', borderRadius: 4, fontSize: 10, background: 'rgba(248,113,113,0.08)', border: '1px solid rgba(248,113,113,0.2)', color: 'var(--accent-red)' }}>
          {error}
        </div>
      )}

      {loading && rows.length === 0 && (
        <div className="panel-empty">Cargando vista...</div>
      )}

      {!loading && rows.length === 0 && !error && (
        <div className="panel-empty">Sin datos para esta vista</div>
      )}

      {rows.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <table className="hud-table">
            <thead>
              <tr>
                {columns.map((col) => (
                  <th key={col}>{col}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, idx) => (
                <tr key={idx}>
                  {columns.map((col) => (
                    <td key={col} title={row[col] != null ? String(row[col]) : ''}>
                      {row[col] != null ? String(row[col]) : '-'}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
