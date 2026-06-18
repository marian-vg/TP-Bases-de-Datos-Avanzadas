import { useState, useCallback } from 'react'
import { AlertTriangle, Crosshair, Gauge, RadioTower, Route, ShieldCheck } from 'lucide-react'
import layout from '../config/zones.layout.json'
import { triggerCatastrophe } from '../api/client'
import RecursoEnMovimiento from './RecursoEnMovimiento'

type MapaZonasProps = {
  state: any
  selectedCatastrophe: string | null
  selectedZoneId: number | null
  onSelectZone: (zonaId: number) => void
  mapLayer: 'incidents' | 'confidence' | 'pressure'
  onReplay: (replay: any) => void
  onSelectZoneCatastropheComplete: () => void
  onCatastropheTriggered: (catastropheId: string) => void
}

function colorForIncidentLoad(count: number) {
  if (count <= 0) return '#34d399'
  if (count === 1) return '#fbbf24'
  return '#f87171'
}

function labelForIncidentLoad(count: number) {
  if (count <= 0) return 'Sin incidentes'
  if (count === 1) return 'Un incidente activo'
  return `${count} incidentes activos`
}

function confidenceColor(value: number) {
  if (value >= 80) return '#34d399'
  if (value >= 50) return '#fbbf24'
  return '#f87171'
}

function pressureColor(value: number) {
  if (value >= 80) return '#f87171'
  if (value >= 55) return '#fb923c'
  if (value >= 30) return '#fbbf24'
  return '#34d399'
}

export default function MapaZonas({
  state,
  selectedCatastrophe,
  selectedZoneId,
  onSelectZone,
  mapLayer,
  onReplay,
  onSelectZoneCatastropheComplete,
  onCatastropheTriggered,
}: MapaZonasProps) {
  const [feedback, setFeedback] = useState<string | null>(null)

  const zonas = state?.zonas || []
  const incidentes = state?.incidentesActivos || []
  const sensores = state?.sensores || []
  const viajes = state?.viajesActivos || []
  const revisiones = state?.eventosEnRevision || []
  const confidenceByZone = state?.sensorConfidenceByZone || {}
  const pressureByZone = state?.cityPressure?.byZone || {}

  const handleZoneClick = useCallback(async (zonaId: number) => {
    onSelectZone(zonaId)
    if (!selectedCatastrophe) return

    setFeedback('Inyectando evento en la ciudad...')
    try {
      const result = await triggerCatastrophe(zonaId, selectedCatastrophe)
      if (result.coverage === 'none') {
        setFeedback('Zona sin sensor compatible para ese evento')
      } else if (result.detectionMode === 'operator_review') {
        const delay = result.reviewDelaySeconds ?? 25
        const confidence = Math.round(Number(result.sensorConfidence || 0))
        setFeedback(`Operador validando señal: confianza ${confidence}. ETA ${delay}s`)
      } else {
        setFeedback(`Sensor confirmó incidente #${result.incidentId}`)
      }
      onReplay({
        id: Date.now(),
        zoneId: zonaId,
        catastropheType: selectedCatastrophe,
        detectionMode: result.detectionMode,
        sensorConfidence: result.sensorConfidence,
        reviewDelaySeconds: result.reviewDelaySeconds,
        incidentId: result.incidentId,
        sensorType: result.sensorType,
      })
      onCatastropheTriggered(selectedCatastrophe)
      onSelectZoneCatastropheComplete()
    } catch (e) {
      setFeedback('Error: ' + (e as Error).message)
    }
    setTimeout(() => setFeedback(null), 3600)
  }, [selectedCatastrophe, onCatastropheTriggered, onSelectZoneCatastropheComplete, onSelectZone, onReplay])

  const incidentesPorZona = incidentes.reduce((acc: any, inc: any) => {
    const zid = inc.fk_zona_id || inc.zona_id || zonas.find((z: any) => z.nombre === inc.zona)?.id_zona
    if (!zid) return acc
    acc[zid] = (acc[zid] || 0) + 1
    return acc
  }, {})

  const sensoresPorZona = sensores.reduce((acc: any, s: any) => {
    const zid = s.fk_zona_id || s.zona_id
    if (!zid) return acc
    acc[zid] = (acc[zid] || 0) + 1
    return acc
  }, {})

  const revisionesPorZona = revisiones.reduce((acc: any, rev: any) => {
    const zid = rev.zona_id
    if (!zid) return acc
    acc[zid] = (acc[zid] || 0) + 1
    return acc
  }, {})

  return (
    <div className="map-container">
      <div className="city-board-glow" />
      <div className="map-scanline" />

      <div className="map-legend">
        {mapLayer === 'incidents' && <>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#34d399' }} />0 incidentes</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#fbbf24' }} />1 incidente</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#f87171' }} />2+ incidentes</span>
        </>}
        {mapLayer === 'confidence' && <>
          <span className="legend-item"><ShieldCheck size={10} style={{ color: '#34d399' }} />Confianza alta</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#fbbf24' }} />Media</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#f87171' }} />Baja</span>
        </>}
        {mapLayer === 'pressure' && <>
          <span className="legend-item"><Gauge size={10} style={{ color: '#34d399' }} />Estable</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#fbbf24' }} />Tensión</span>
          <span className="legend-item"><span className="legend-dot" style={{ backgroundColor: '#f87171' }} />Colapso</span>
        </>}
        <span className="legend-item" style={{ marginLeft: 4 }}><Route size={10} style={{ color: 'var(--accent-cyan)' }} />{viajes.length} viajes</span>
        <span className="legend-item"><RadioTower size={10} style={{ color: 'var(--accent-violet)' }} />{sensores.length} sensores</span>
        <span className="legend-item"><AlertTriangle size={10} style={{ color: 'var(--accent-amber)' }} />{incidentes.length} inc.</span>
      </div>

      {feedback && (
        <div className="map-overlay-msg map-overlay-msg--feedback">
          {feedback}
        </div>
      )}

      {selectedCatastrophe && (
        <div className="map-overlay-msg pulse-glow map-overlay-msg--targeting">
          <Crosshair size={12} style={{ marginRight: 4, display: 'inline' }} />
          Seleccioná una zona para provocar el evento
        </div>
      )}

      <svg className="map-svg" viewBox="0 0 700 520" preserveAspectRatio="xMidYMid meet">
        <defs>
          <pattern id="city-grid" width="28" height="28" patternUnits="userSpaceOnUse">
            <path d="M 28 0 L 0 0 0 28" fill="none" stroke="rgba(56,189,248,0.06)" strokeWidth="1" />
          </pattern>
          <radialGradient id="board-bg" cx="50%" cy="50%" r="60%">
            <stop stopColor="#151d28" offset="0%" />
            <stop stopColor="#0a0e14" offset="100%" />
          </radialGradient>
          <filter id="glow">
            <feGaussianBlur stdDeviation="3" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <rect x="0" y="0" width="700" height="520" fill="url(#board-bg)" />
        <rect x="0" y="0" width="700" height="520" fill="url(#city-grid)" />

        <g opacity="0.12">
          {layout.zones.map((z: any, index: number) => (
            <rect
              key={`block-${z.id}`}
              x={z.x - 34}
              y={z.y - 22}
              width={index % 3 === 0 ? 82 : 68}
              height={index % 2 === 0 ? 42 : 52}
              rx="4"
              fill="rgba(56,189,248,0.12)"
              transform={`rotate(${index % 2 === 0 ? -8 : 7} ${z.x} ${z.y})`}
            />
          ))}
        </g>

        {layout.connections.map(([a, b], i) => {
          const za = layout.zones.find((z: any) => z.id === a)
          const zb = layout.zones.find((z: any) => z.id === b)
          if (!za || !zb) return null
          return <line key={i} x1={za.x} y1={za.y} x2={zb.x} y2={zb.y} stroke="rgba(56,189,248,0.14)" strokeWidth="2" strokeLinecap="round" />
        })}

        {layout.zones.map((z: any) => {
          const incCount = incidentesPorZona[z.id] || 0
          const senCount = sensoresPorZona[z.id] || 0
          const reviewCount = revisionesPorZona[z.id] || 0
          const confidence = confidenceByZone[String(z.id)]?.average ?? 0
          const pressure = pressureByZone[String(z.id)]?.score ?? 0
          const color = mapLayer === 'confidence'
            ? confidenceColor(confidence)
            : mapLayer === 'pressure'
              ? pressureColor(pressure)
              : colorForIncidentLoad(incCount)
          const isSelected = selectedZoneId === z.id
          const isHot = incCount > 0
          const isTargeting = !!selectedCatastrophe
          const radius = incCount >= 2 ? 15 : incCount === 1 ? 12 : 9

          return (
            <g key={z.id} className="zone-node" onClick={() => handleZoneClick(z.id)} style={{ cursor: isTargeting ? 'crosshair' : 'pointer' }}>
              <title>{`${z.name}: ${labelForIncidentLoad(incCount)}. Sensores ${senCount}. Confianza ${confidence}. Presión ${pressure}. Revisiones ${reviewCount}.`}</title>
              <circle cx={z.x} cy={z.y} r={isSelected ? 44 : 36} fill={color} fillOpacity={isSelected ? 0.16 : 0.05} />
              {mapLayer === 'pressure' && pressure > 0 && <circle cx={z.x} cy={z.y} r={34 + pressure / 7} fill={color} fillOpacity={Math.min(0.18, pressure / 520)} />}
              {mapLayer === 'confidence' && confidence > 0 && <circle cx={z.x} cy={z.y} r={30} fill="none" stroke={color} strokeWidth="3" strokeOpacity={0.18 + confidence / 180} />}
              {isHot && <circle className="zone-alert-ring" cx={z.x} cy={z.y} r="38" fill="none" stroke={color} />}
              {reviewCount > 0 && <circle className="zone-review-ring" cx={z.x} cy={z.y} r="45" fill="none" stroke="var(--accent-cyan)" />}
              <polygon
                points={`${z.x},${z.y - 26} ${z.x + 28},${z.y} ${z.x},${z.y + 26} ${z.x - 28},${z.y}`}
                fill="rgba(21,29,40,0.88)"
                stroke={isSelected ? 'var(--accent-cyan)' : color}
                strokeWidth={isSelected ? 2.8 : 1.6}
                strokeOpacity={0.9}
              />
              <circle cx={z.x} cy={z.y} r={isSelected ? radius + 3 : radius} fill={color} fillOpacity="0.9" stroke="rgba(21,29,40,0.7)" strokeWidth="2" filter={isHot ? 'url(#glow)' : undefined} />
              <text x={z.x} y={z.y - 38} className="zone-label">{z.name}</text>
              <text x={z.x} y={z.y + 42} className="zone-label zone-meta">
                {mapLayer === 'confidence' ? `C:${Math.round(confidence)} S:${senCount}` : mapLayer === 'pressure' ? `P:${Math.round(pressure)} I:${incCount}` : `S:${senCount} I:${incCount} R:${reviewCount}`}
              </text>
            </g>
          )
        })}

        <RecursoEnMovimiento trips={viajes} />
      </svg>

      {!selectedCatastrophe && (
        <div className="map-overlay-msg map-overlay-msg--hint">
          <Crosshair size={11} style={{ marginRight: 4, display: 'inline', color: 'var(--accent-emerald)' }} />
          Click en una zona para abrir su ficha operativa
        </div>
      )}
    </div>
  )
}
