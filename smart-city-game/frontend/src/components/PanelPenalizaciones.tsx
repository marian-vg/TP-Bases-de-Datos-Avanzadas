export default function PanelPenalizaciones({ state }: { state: any }) {
  const penalizaciones = state?.penalizaciones || []

  if (penalizaciones.length === 0) {
    return <div className="panel-empty">Sin penalizaciones recientes</div>
  }

  return (
    <table className="hud-table">
      <thead>
        <tr>
          <th>Recurso</th>
          <th>Tipo</th>
          <th>Fecha</th>
          <th>Puntos</th>
          <th>Motivo</th>
        </tr>
      </thead>
      <tbody>
        {penalizaciones.map((p: any, idx: number) => (
          <tr key={idx}>
            <td style={{ fontWeight: 600 }}>{p.recurso || p.fk_recurso_id || '-'}</td>
            <td>
              <span
                className="badge-severity"
                style={{
                  background: (p.tipo_penalizacion || '').toLowerCase().includes('grave')
                    ? 'rgba(248,113,113,0.12)' : 'rgba(251,191,36,0.1)',
                  color: (p.tipo_penalizacion || '').toLowerCase().includes('grave')
                    ? 'var(--accent-red)' : 'var(--accent-amber)',
                  border: `1px solid ${(p.tipo_penalizacion || '').toLowerCase().includes('grave')
                    ? 'rgba(248,113,113,0.25)' : 'rgba(251,191,36,0.2)'}`,
                }}
              >
                {p.tipo_penalizacion || p.tipo || '-'}
              </span>
            </td>
            <td>{p.fecha || p.fecha_hora || '-'}</td>
            <td style={{ fontFamily: 'var(--font-mono)', fontWeight: 700, color: 'var(--accent-red)' }}>
              -{p.puntaje || p.puntos || 0}
            </td>
            <td>{p.motivo || '-'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
