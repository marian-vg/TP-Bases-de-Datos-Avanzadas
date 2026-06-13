import { useState, useCallback } from 'react'
import { AlertTriangle, Crosshair, RadioTower, Route } from 'lucide-react'
import layout from '../config/zones.layout.json'
import { triggerCatastrophe } from '../api/client'
import RecursoEnMovimiento from './RecursoEnMovimiento'

const ZONE_COLORS: Record<string, string> = {
  Bajo: '#34d399',
  Moderado: '#fbbf24',
  Alto: '#fb923c',
  Critico: '#f87171',
}

type MapaZonasProps = {
  state: any
  selectedCatastrophe: string | null
  onSelectZoneCatastropheComplete: () => void
  onCatastropheTriggered: (catastropheId: string) => void
}

export default function MapaZonas({
  state,
  selectedCatastrophe,
  onSelectZoneCatastropheComplete,
  onCatastropheTriggered,
}: MapaZonasProps) {
  const [selectedZone, setSelectedZone] = useState<number | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)

  const zonas = state?.zonas || []
  const incidentes = state?.incidentesActivos || []
  const sensores = state?.sensores || []
  const viajes = state?.viajesActivos || []

  const handleZoneClick = useCallback(async (zonaId: number) => {
    if (!selectedCatastrophe) {
      setSelectedZone(zonaId)
      return
    }
    setFeedback('Enviando evento...')
    try {
      const result = await triggerCatastrophe(zonaId, selectedCatastrophe)
      if (result.coverage === 'none') {
        setFeedback('Zona sin cobertura compatible')
      } else if (result.detectionMode === 'operator_review') {
        setFeedback(`Revision operador por baja confianza (${result.sensorConfidence})`)
      } else {
        setFeedback(`Incidente #${result.incidentId} creado`)
      }
      onCatastropheTriggered(selectedCatastrophe)
      onSelectZoneCatastropheComplete()
    } catch (e) {
      setFeedback('Error: ' + (e as Error).message)
    }
    setTimeout(() => setFeedback(null), 3000)
  }, [selectedCatastrophe, onCatastropheTriggered, onSelectZoneCatastropheComplete])

  const incidentesPorZona = incidentes.reduce((acc: any, inc: any) => {
    const zid = inc.zona || inc.fk_zona_id
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

  return (
    <div className="map-container">
      <div className="city-board-glow" />
      <div className="map-scanline" />

      {/* Legend */}
      <div className="map-legend">
        {Object.entries(ZONE_COLORS).map(([level, color]) => (
          <span key={level} className="legend-item">
            <span className="legend-dot" style={{ backgroundColor: color }} />
            {level}
          </span>
        ))}
        <span className="legend-item" style={{ marginLeft: 4 }}>
          <Route size={10} style={{ color: 'var(--accent-cyan)' }} />
          {viajes.length} viajes
        </span>
        <span className="legend-item">
          <RadioTower size={10} style={{ color: 'var(--accent-violet)' }} />
          {sensores.length} sensores
        </span>
        <span className="legend-item">
          <AlertTriangle size={10} style={{ color: 'var(--accent-amber)' }} />
          {incidentes.length} inc.
        </span>
      </div>

      {/* Feedback message */}
      {feedback && (
        <div
          className="map-overlay-msg"
          style={{
            top: 8,
            right: 8,
            background: 'rgba(10,14,20,0.9)',
            borderColor: 'rgba(56,189,248,0.3)',
            color: 'var(--accent-cyan)',
          }}
        >
          {feedback}
        </div>
      )}

      {/* Catastrophe targeting hint */}
      {selectedCatastrophe && (
        <div
          className="map-overlay-msg pulse-glow"
          style={{
            bottom: 8,
            left: '50%',
            transform: 'translateX(-50%)',
            background: 'rgba(248,113,113,0.1)',
            borderColor: 'rgba(248,113,113,0.4)',
            color: 'var(--accent-red)',
          }}
        >
          <Crosshair size={12} style={{ marginRight: 4, display: 'inline' }} />
          Seleccioná una zona para desplegar la catástrofe
        </div>
      )}

      {/* SVG Map */}
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

        {/* Building blocks */}
        <g opacity="0.15">
          {layout.zones.map((z: any, index: number) => (
            <rect
              key={`block-${z.id}`}
              x={z.x - 34}
              y={z.y - 22}
              width={index % 3 === 0 ? 82 : 68}
              height={index % 2 === 0 ? 42 : 52}
              rx="4"
              fill={index % 4 === 0 ? 'rgba(251,191,36,0.15)' : index % 4 === 1 ? 'rgba(52,211,153,0.12)' : index % 4 === 2 ? 'rgba(56,189,248,0.1)' : 'rgba(248,113,113,0.1)'}
              transform={`rotate(${index % 2 === 0 ? -8 : 7} ${z.x} ${z.y})`}
            />
          ))}
        </g>

        {/* Connection lines */}
        {layout.connections.map(([a, b], i) => {
          const za = layout.zones.find((z: any) => z.id === a)
          const zb = layout.zones.find((z: any) => z.id === b)
          if (!za || !zb) return null
          return (
            <line
              key={i}
              x1={za.x}
              y1={za.y}
              x2={zb.x}
              y2={zb.y}
              stroke="rgba(56,189,248,0.12)"
              strokeWidth="2"
              strokeLinecap="round"
            />
          )
        })}

        {/* Zone nodes */}
        {layout.zones.map((z: any) => {
          const zonaData = zonas.find((zz: any) => zz.id_zona === z.id)
          const riesgo = zonaData?.nivel_riesgo || 'Bajo'
          const color = ZONE_COLORS[riesgo] || ZONE_COLORS.Bajo
          const incCount = incidentesPorZona[z.id] || 0
          const senCount = sensoresPorZona[z.id] || 0
          const isSelected = selectedZone === z.id
          const isHot = incCount > 0
          const isTargeting = !!selectedCatastrophe

          return (
            <g
              key={z.id}
              className="zone-node"
              onClick={() => handleZoneClick(z.id)}
              style={{ cursor: isTargeting ? 'crosshair' : 'pointer' }}
            >
              {/* Outer glow */}
              <circle
                cx={z.x}
                cy={z.y}
                r={isSelected ? 42 : 36}
                fill={color}
                fillOpacity={isSelected ? 0.12 : 0.04}
              />

              {/* Alert ring for active incidents */}
              {isHot && (
                <circle
                  className="zone-alert-ring"
                  cx={z.x}
                  cy={z.y}
                  r="38"
                  fill="none"
                  stroke={color}
                />
              )}

              {/* Diamond shape */}
              <polygon
                points={`${z.x},${z.y - 26} ${z.x + 28},${z.y} ${z.x},${z.y + 26} ${z.x - 28},${z.y}`}
                fill="rgba(21,29,40,0.85)"
                stroke={isSelected ? 'var(--accent-cyan)' : color}
                strokeWidth={isSelected ? 2.5 : 1.5}
                strokeOpacity={0.8}
              />

              {/* Core dot */}
              <circle
                cx={z.x}
                cy={z.y}
                r={isSelected ? 13 : 10}
                fill={color}
                fillOpacity="0.85"
                stroke="rgba(21,29,40,0.6)"
                strokeWidth="2"
                filter={isHot ? 'url(#glow)' : undefined}
              />

              {/* Name label */}
              <text x={z.x} y={z.y - 38} className="zone-label">{z.name}</text>

              {/* Metadata label */}
              <text x={z.x} y={z.y + 42} className="zone-label zone-meta">
                S:{senCount} I:{incCount}
              </text>
            </g>
          )
        })}

        {/* Moving resources */}
        <RecursoEnMovimiento trips={viajes} />
      </svg>

      {/* Status bar overlay */}
      {!selectedCatastrophe && (
        <div
          className="map-overlay-msg"
          style={{
            bottom: 8,
            left: 8,
            background: 'rgba(10,14,20,0.8)',
            borderColor: 'var(--hud-border)',
            color: 'var(--hud-text-muted)',
            fontSize: 10,
          }}
        >
          <Crosshair size={11} style={{ marginRight: 4, display: 'inline', color: 'var(--accent-emerald)' }} />
          Click en una zona para inspección rápida
        </div>
      )}
    </div>
  )
}
