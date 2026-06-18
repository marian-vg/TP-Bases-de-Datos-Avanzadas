import { Activity, Hourglass, RadioTower, ShieldAlert } from 'lucide-react'

type Replay = {
  id: number
  zoneId: number
  catastropheType: string
  detectionMode?: string
  sensorConfidence?: number
  reviewDelaySeconds?: number
  incidentId?: number | null
  sensorType?: string
}

export default function ReplayOverlay({ replay }: { replay: Replay | null }) {
  if (!replay) return null
  const review = replay.detectionMode === 'operator_review'
  return (
    <div key={replay.id} className={`replay-overlay ${review ? 'replay-overlay--review' : 'replay-overlay--confirmed'}`}>
      <div className="replay-step replay-step--attack"><ShieldAlert size={14} /> Evento inyectado en zona {replay.zoneId}</div>
      <div className="replay-step replay-step--sensor"><RadioTower size={14} /> {replay.sensorType || 'Sensor'} · confianza {Math.round(Number(replay.sensorConfidence || 0))}</div>
      <div className="replay-step replay-step--outcome">
        {review ? <Hourglass size={14} /> : <Activity size={14} />}
        {review ? `Operador validando · ETA ${replay.reviewDelaySeconds || 25}s` : `Incidente #${replay.incidentId} confirmado`}
      </div>
    </div>
  )
}
