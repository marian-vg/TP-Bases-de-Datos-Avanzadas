import { useState, useCallback } from 'react'
import { AlertTriangle, Crosshair, Gauge, RadioTower, Route, ShieldCheck } from 'lucide-react'
import layout from '../config/zones.layout.json'
import { triggerCatastrophe } from '../api/client'
import RecursoEnMovimiento from './RecursoEnMovimiento'

type MapaZonasProps = {
  state: any
  selectedCatastrophe: string | null
  selectedZoneId: number | null
  onSelectZone: (zonaId: number | null) => void
  mapLayer: 'incidents' | 'confidence' | 'pressure'
  onReplay: (replay: any) => void
  onSelectZoneCatastropheComplete: () => void
  onCatastropheTriggered: (catastropheId: string) => void
}

function colorForGravity(gravity: string | number | null) {
  if (!gravity) return 'var(--accent-emerald)';
  
  let gNum = 0;
  if (typeof gravity === 'number') {
    gNum = gravity;
  } else {
    const name = String(gravity).toLowerCase();
    if (name === 'catastrófica' || name === 'catastrofica') gNum = 5;
    else if (name === 'crítica' || name === 'critica') gNum = 4;
    else if (name === 'alta') gNum = 3;
    else if (name === 'moderada') gNum = 2;
    else if (name === 'baja') gNum = 1;
  }
  
  if (gNum === 5) return 'var(--accent-violet)'; // Violeta
  if (gNum === 4) return 'var(--accent-red)'; // Rojo
  if (gNum === 3) return 'var(--risk-high)'; // Naranja
  if (gNum === 2 || gNum === 1) return 'var(--accent-amber)'; // Amarillo
  return 'var(--accent-emerald)';
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
  const [dragOverZoneId, setDragOverZoneId] = useState<number | null>(null)

  const zonas = state?.zonas || []
  const incidentes = state?.incidentesActivos || []
  const sensores = state?.sensores || []
  const viajes = state?.viajesActivos || []
  const revisiones = state?.eventosEnRevision || []
  const confidenceByZone = state?.sensorConfidenceByZone || {}
  const pressureByZone = state?.cityPressure?.byZone || {}

  const triggerCatastropheForZone = useCallback(async (zonaId: number, catId: string) => {
    setFeedback('Inyectando evento en la ciudad...')
    try {
      const result = await triggerCatastrophe(zonaId, catId)
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
        catastropheType: catId,
        detectionMode: result.detectionMode,
        sensorConfidence: result.sensorConfidence,
        reviewDelaySeconds: result.reviewDelaySeconds,
        incidentId: result.incidentId,
        sensorType: result.sensorType,
      })
      onCatastropheTriggered(catId)
      onSelectZoneCatastropheComplete()
    } catch (e) {
      setFeedback('Error: ' + (e as Error).message)
    }
    setTimeout(() => setFeedback(null), 3600)
  }, [onCatastropheTriggered, onSelectZoneCatastropheComplete, onReplay])

  const handleZoneClick = useCallback(async (zonaId: number) => {
    if (selectedZoneId === zonaId) {
      onSelectZone(null)
      return
    }
    onSelectZone(zonaId)
    if (!selectedCatastrophe) return
    await triggerCatastropheForZone(zonaId, selectedCatastrophe)
  }, [selectedCatastrophe, selectedZoneId, onSelectZone, triggerCatastropheForZone])

  const handleDrop = useCallback(async (e: React.DragEvent, zonaId: number) => {
    e.preventDefault()
    setDragOverZoneId(null)
    const catId = e.dataTransfer.getData('text/plain') || selectedCatastrophe
    if (catId) {
      onSelectZone(zonaId)
      await triggerCatastropheForZone(zonaId, catId)
    }
  }, [selectedCatastrophe, onSelectZone, triggerCatastropheForZone])

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

  const revisionActivaPorZona = revisiones.reduce((acc: any, rev: any) => {
    const zid = rev.zona_id
    if (!zid) return acc
    const current = acc[zid]
    if (!current || Number(rev.seconds_remaining || 0) < Number(current.seconds_remaining || 0)) {
      acc[zid] = rev
    }
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

        <rect x="0" y="0" width="700" height="520" fill="url(#board-bg)" onClick={() => onSelectZone(null)} />
        <rect x="0" y="0" width="700" height="520" fill="url(#city-grid)" onClick={() => onSelectZone(null)} />

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
          const activeReview = revisionActivaPorZona[z.id]
          const reviewDelay = Number(activeReview?.delay_seconds || 25)
          const reviewRemaining = Number(activeReview?.seconds_remaining || 0)
          const reviewRatio = activeReview ? Math.max(0, Math.min(1, reviewRemaining / Math.max(1, reviewDelay))) : 0
          const confidence = confidenceByZone[String(z.id)]?.average ?? 0
          const pressure = pressureByZone[String(z.id)]?.score ?? 0

          // Determinar el incidente más grave de la zona
          const incsDeZona = incidentes.filter((inc: any) => {
            const zid = inc.fk_zona_id || inc.zona_id || zonas.find((zone: any) => zone.nombre === inc.zona)?.id_zona;
            return zid === z.id;
          });
          
          let maxGrav: string | number | null = null;
          if (incsDeZona.length > 0) {
            const pesos: Record<string, number> = {
              'baja': 1,
              'moderada': 2,
              'alta': 3,
              'crítica': 4,
              'critica': 4,
              'catastrófica': 5,
              'catastrofica': 5
            };
            let maxWeight = 0;
            incsDeZona.forEach((inc: any) => {
              const name = String(inc.gravedad || 'Baja').toLowerCase();
              const weight = pesos[name] || inc.gravedad_id || 1;
              if (weight > maxWeight) {
                maxWeight = weight;
                maxGrav = inc.gravedad || inc.gravedad_id;
              }
            });
          }

          const color = mapLayer === 'confidence'
            ? confidenceColor(confidence)
            : mapLayer === 'pressure'
              ? pressureColor(pressure)
              : maxGrav
                ? colorForGravity(maxGrav)
                : '#34d399'
          const isSelected = selectedZoneId === z.id
          const isHot = incCount > 0
          const isTargeting = !!selectedCatastrophe
          const radius = incCount >= 2 ? 15 : incCount === 1 ? 12 : 9

          const reviewColor = activeReview ? colorForGravity(activeReview.gravedad_id) : 'var(--accent-emerald)';

          return (
            <g
              key={z.id}
              className="zone-node"
              onClick={() => handleZoneClick(z.id)}
              style={{ cursor: isTargeting ? 'crosshair' : 'pointer' }}
              onDragOver={(e) => {
                if (selectedCatastrophe) {
                  e.preventDefault()
                }
              }}
              onDragEnter={() => {
                if (selectedCatastrophe) {
                  setDragOverZoneId(z.id)
                }
              }}
              onDragLeave={() => setDragOverZoneId(null)}
              onDrop={(e) => handleDrop(e, z.id)}
            >
              <title>{`${z.name}: ${labelForIncidentLoad(incCount)}. Sensores ${senCount}. Confianza ${confidence}. Presión ${pressure}. Revisiones ${reviewCount}.`}</title>
              <circle
                cx={z.x}
                cy={z.y}
                r={isSelected || dragOverZoneId === z.id ? 44 : 36}
                fill={dragOverZoneId === z.id ? 'var(--accent-cyan)' : color}
                fillOpacity={isSelected || dragOverZoneId === z.id ? 0.22 : 0.05}
                stroke={dragOverZoneId === z.id ? 'var(--accent-cyan)' : 'none'}
                strokeWidth={dragOverZoneId === z.id ? 2 : 0}
                style={{ transition: 'all 0.15s ease' }}
              />
              {mapLayer === 'pressure' && pressure > 0 && <circle cx={z.x} cy={z.y} r={34 + pressure / 7} fill={color} fillOpacity={Math.min(0.18, pressure / 520)} />}
              {mapLayer === 'confidence' && confidence > 0 && <circle cx={z.x} cy={z.y} r={30} fill="none" stroke={color} strokeWidth="3" strokeOpacity={0.18 + confidence / 180} />}
              {activeReview && (
                <circle
                  className="operator-countdown-bubble"
                  cx={z.x}
                  cy={z.y}
                  r={12 + reviewRatio * 34}
                  fill={reviewColor}
                  fillOpacity={0.08 + reviewRatio * 0.12}
                  stroke={reviewColor}
                  strokeWidth="2"
                  strokeOpacity={0.35 + reviewRatio * 0.45}
                  style={{
                    filter: `drop-shadow(0 0 10px ${reviewColor})`
                  }}
                />
              )}
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
                {mapLayer === 'confidence' ? `Conf:${Math.round(confidence)}% Sens:${senCount}` : mapLayer === 'pressure' ? `Pres:${Math.round(pressure)}% Inc:${incCount}` : `Sens:${senCount} Inc:${incCount} Rev:${reviewCount}`}
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
