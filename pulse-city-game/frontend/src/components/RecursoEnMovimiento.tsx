import layout from '../config/zones.layout.json'

type Trip = {
  assignment_id: number
  zona_origen: number
  zona_destino: number
  arrived: boolean
  finished: boolean
  is_late: boolean
}

function zonePoint(zoneId: number) {
  return layout.zones.find((zone: any) => zone.id === zoneId)
}

export default function RecursoEnMovimiento({ trips }: { trips: Trip[] }) {
  return (
    <g className="moving-resources">
      {trips.map((trip) => {
        const origin = zonePoint(trip.zona_origen)
        const target = zonePoint(trip.zona_destino)
        if (!origin || !target || trip.finished) return null

        const x = trip.arrived ? target.x : (origin.x + target.x) / 2
        const y = trip.arrived ? target.y : (origin.y + target.y) / 2

        return (
          <g key={trip.assignment_id} className="moving-resource">
            <line
              x1={origin.x}
              y1={origin.y}
              x2={target.x}
              y2={target.y}
              className={trip.is_late ? 'trip-line late' : 'trip-line'}
            />
            <circle cx={x} cy={y} r="7" className={trip.is_late ? 'resource-dot late' : 'resource-dot'} />
            <text x={x} y={y - 11} className="resource-label">A{trip.assignment_id}</text>
          </g>
        )
      })}
    </g>
  )
}
