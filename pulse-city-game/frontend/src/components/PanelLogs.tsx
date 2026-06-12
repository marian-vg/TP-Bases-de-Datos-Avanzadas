export default function PanelLogs({ state }: { state: any }) {
  const logs = state?.logsRecientes || []

  if (logs.length === 0) {
    return <div className="panel-empty">Sin logs recientes</div>
  }

  const getOpStyle = (op: string) => {
    const o = String(op || '').toLowerCase()
    if (o === 'insert') {
      return {
        bg: 'rgba(52,211,153,0.12)',
        color: 'var(--accent-emerald)',
        border: 'rgba(52,211,153,0.25)',
      }
    }
    if (o === 'delete') {
      return {
        bg: 'rgba(248,113,113,0.12)',
        color: 'var(--accent-red)',
        border: 'rgba(248,113,113,0.25)',
      }
    }
    return {
      bg: 'rgba(251,191,36,0.1)',
      color: 'var(--accent-amber)',
      border: 'rgba(251,191,36,0.2)',
    }
  }

  return (
    <div style={{ padding: '4px 0' }}>
      <table className="hud-table">
        <thead>
          <tr>
            <th>Timestamp</th>
            <th>Tabla</th>
            <th>Operación</th>
            <th>Trigger</th>
          </tr>
        </thead>
        <tbody>
          {logs.map((log: any, idx: number) => {
            const opStyle = getOpStyle(log.operacion || '')
            return (
              <tr key={idx}>
                <td style={{ fontFamily: 'var(--font-mono)', color: 'var(--hud-text-muted)' }}>
                  {log.timestamp || log.fecha_hora || '-'}
                </td>
                <td style={{ fontWeight: 600 }}>{log.tablaafectada || log.tabla || '-'}</td>
                <td>
                  <span
                    className="badge-severity"
                    style={{
                      background: opStyle.bg,
                      color: opStyle.color,
                      border: `1px solid ${opStyle.border}`,
                    }}
                  >
                    {log.operacion || '-'}
                  </span>
                </td>
                <td style={{ fontFamily: 'var(--font-mono)', fontSize: 10 }}>
                  {log.trigger_disparador || log.trigger || '-'}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
