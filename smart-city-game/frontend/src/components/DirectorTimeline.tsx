import { Activity, Ambulance, Crosshair, DatabaseZap, Hourglass, RadioTower } from 'lucide-react'
import { formatFeedMessage } from '../lib/feedFormatter'

const ICONS: Record<string, typeof Activity> = {
  attack: Crosshair,
  sensor: RadioTower,
  operator: Hourglass,
  resource: Ambulance,
  penalty: DatabaseZap,
}

export default function DirectorTimeline({ state }: { state: any }) {
  const feed = state?.gameFeed || []
  if (feed.length === 0) {
    return <div className="panel-empty">Todavía no hay historia operativa. Provocá un evento para ver reaccionar a la ciudad.</div>
  }
  return (
    <div className="director-timeline">
      {feed.map((item: any) => {
        const Icon = ICONS[item.kind] || Activity
        const time = item.sim_time ? new Date(item.sim_time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '--:--'
        const zonaObj = state?.zonas?.find((z: any) => z.id_zona === item.zona_id)
        const zonaNombre = zonaObj ? zonaObj.nombre : (item.zona || item.zona_id)

        return (
          <article key={item.id} className={`timeline-event timeline-event--${item.severity || 'info'}`}>
            <div className="timeline-event-icon"><Icon size={13} /></div>
            <div className="timeline-event-body">
              <div className="timeline-event-topline"><strong>{item.title}</strong><span>{time}</span></div>
              <p>{formatFeedMessage(item.message, state)}</p>
              {item.zona_id && <small>Zona {zonaNombre}</small>}
            </div>
          </article>
        )
      })}
    </div>
  )
}
