import { useState } from 'react'
import { AlertTriangle, Ambulance, Hourglass, MapPin, X } from 'lucide-react'
import PanelIncidentes from './PanelIncidentes'
import PanelRecursos from './PanelRecursos'
import PanelEventosRevision from './PanelEventosRevision'

interface GameSidebarProps {
  state: any
  selectedZoneId: number | null
  onSelectZone: (zonaId: number | null) => void
}

type SidebarTab = 'incidentes' | 'recursos' | 'revision'

const TABS: { id: SidebarTab; label: string; icon: typeof AlertTriangle; countKey: string; hint: string }[] = [
  { id: 'incidentes', label: 'Incidentes', icon: AlertTriangle, countKey: 'incidentesActivos', hint: 'Incidentes activos, gravedad, estado y cierre manual' },
  { id: 'recursos', label: 'Recursos', icon: Ambulance, countKey: 'recursos', hint: 'Recursos por zona, disponibilidad y reactivación' },
  { id: 'revision', label: 'Revisión', icon: Hourglass, countKey: 'eventosEnRevision', hint: 'Eventos que existen en el juego y esperan validación operativa' },
]

function zoneName(state: any, selectedZoneId: number | null) {
  if (!selectedZoneId) return null
  return state?.zonas?.find((zona: any) => zona.id_zona === selectedZoneId)?.nombre || `Zona ${selectedZoneId}`
}

export default function GameSidebar({ state, selectedZoneId, onSelectZone }: GameSidebarProps) {
  const [activeTab, setActiveTab] = useState<SidebarTab>('incidentes')
  const selectedName = zoneName(state, selectedZoneId)
  const confidence = selectedZoneId ? state?.sensorConfidenceByZone?.[String(selectedZoneId)] : null
  const pressure = selectedZoneId ? state?.cityPressure?.byZone?.[String(selectedZoneId)] : null

  return (
    <div className="game-sidebar">
      <div className="zone-focus-card">
        <div>
          <span className="zone-focus-kicker"><MapPin size={12} /> Ficha operativa</span>
          <strong>{selectedName || 'Toda la ciudad'}</strong>
          <small>{selectedZoneId ? 'Filtrando incidentes, recursos y revisiones de la zona.' : 'Click en una zona del mapa para inspeccionarla.'}</small>
          {selectedZoneId && (
            <div className="zone-focus-metrics">
              <span><b>{Math.round(confidence?.average || 0)}</b> confianza</span>
              <span><b>{Math.round(pressure?.score || 0)}</b> presión</span>
              <span><b>{(state?.sensores || []).filter((s: any) => s.fk_zona_id === selectedZoneId).length}</b> sensores</span>
            </div>
          )}
        </div>
        {selectedZoneId && (
          <button className="zone-focus-clear" type="button" onClick={() => onSelectZone(null)} title="Quitar filtro de zona">
            <X size={13} />
          </button>
        )}
      </div>

      <div className="sidebar-tabs">
        {TABS.map((tab) => {
          const Icon = tab.icon
          const count = state?.[tab.countKey]?.length ?? 0
          return (
            <button
              key={tab.id}
              type="button"
              className={`sidebar-tab ${activeTab === tab.id ? 'active' : ''}`}
              onClick={() => setActiveTab(tab.id)}
              title={tab.hint}
            >
              <Icon size={12} />
              {tab.label}
              {count > 0 && <span className="sidebar-tab-badge">{count}</span>}
            </button>
          )
        })}
      </div>

      <div className="sidebar-content">
        {activeTab === 'incidentes' && <PanelIncidentes state={state} selectedZoneId={selectedZoneId} />}
        {activeTab === 'recursos' && <PanelRecursos state={state} selectedZoneId={selectedZoneId} />}
        {activeTab === 'revision' && <PanelEventosRevision state={state} selectedZoneId={selectedZoneId} />}
      </div>
    </div>
  )
}
