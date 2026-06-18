import layout from '../config/zones.layout.json'

type Trip = {
  assignment_id: number
  zona_origen: number
  zona_destino: number
  arrived: boolean
  finished: boolean
  is_late: boolean
  progress?: number
}

type Point = { id: number; x: number; y: number }

function zonePoint(zoneId: number): Point | undefined {
  return layout.zones.find((zone: any) => zone.id === zoneId)
}

function routeBetween(originId: number, targetId: number): Point[] {
  const origin = zonePoint(originId)
  const target = zonePoint(targetId)
  if (!origin || !target) return []
  if (originId === targetId) return [origin]

  const graph = new Map<number, number[]>()
  layout.connections.forEach(([a, b]: any) => {
    graph.set(a, [...(graph.get(a) || []), b])
    graph.set(b, [...(graph.get(b) || []), a])
  })

  const queue: number[][] = [[originId]]
  const seen = new Set<number>([originId])
  while (queue.length) {
    const path = queue.shift() || []
    const last = path[path.length - 1]
    if (last === targetId) return path.map((id) => zonePoint(id)).filter(Boolean) as Point[]
    for (const next of graph.get(last) || []) {
      if (seen.has(next)) continue
      seen.add(next)
      queue.push([...path, next])
    }
  }

  return [origin, target]
}

function pathD(points: Point[]) {
  return points.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ')
}

function interpolate(points: Point[], progress: number) {
  if (points.length === 0) return { x: 0, y: 0 }
  if (points.length === 1) return points[0]

  const lengths = points.slice(1).map((point, index) => {
    const prev = points[index]
    return Math.hypot(point.x - prev.x, point.y - prev.y)
  })
  const total = lengths.reduce((sum, length) => sum + length, 0) || 1
  let distance = Math.max(0, Math.min(1, progress)) * total

  for (let index = 0; index < lengths.length; index += 1) {
    const segment = lengths[index]
    if (distance <= segment) {
      const start = points[index]
      const end = points[index + 1]
      const ratio = segment === 0 ? 0 : distance / segment
      return {
        x: start.x + (end.x - start.x) * ratio,
        y: start.y + (end.y - start.y) * ratio,
      }
    }
    distance -= segment
  }

  return points[points.length - 1]
}

export default function RecursoEnMovimiento({ trips }: { trips: Trip[] }) {
  return (
    <g className="moving-resources">
      {trips.map((trip) => {
        const route = routeBetween(trip.zona_origen, trip.zona_destino)
        if (route.length === 0 || trip.finished) return null
        const point = interpolate(route, trip.arrived ? 1 : trip.progress ?? 0.5)
        const routePath = pathD(route)
        const label = `A${trip.assignment_id}`

        return (
          <g key={trip.assignment_id} className="moving-resource">
            <path d={routePath} className={trip.is_late ? 'trip-line late' : 'trip-line'} />
            {route.map((node) => <circle key={`${trip.assignment_id}-${node.id}`} cx={node.x} cy={node.y} r="3" className="trip-hop" />)}
            <circle cx={point.x} cy={point.y} r="7" className={trip.is_late ? 'resource-dot late' : 'resource-dot'} />
            <circle cx={point.x} cy={point.y} r="13" className={trip.is_late ? 'resource-pulse late' : 'resource-pulse'} />
            <text x={point.x} y={point.y - 13} className="resource-label">{label}</text>
            <title>{`Asignación ${label}: recurso viajando por la red de zonas ${trip.zona_origen} -> ${trip.zona_destino}`}</title>
          </g>
        )
      })}
    </g>
  )
}
