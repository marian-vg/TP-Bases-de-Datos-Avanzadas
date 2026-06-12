import { useState } from 'react'
import { AlertTriangle, Ambulance, Hourglass } from 'lucide-react'
import PanelIncidentes from './PanelIncidentes'
import PanelRecursos from './PanelRecursos'
import PanelEventosRevision from './PanelEventosRevision'

interface GameSidebarProps {
  state: any
}

type SidebarTab = 'incidentes' | 'recursos' | 'revision'

const TABS: { id: SidebarTab; label: string; icon: typeof AlertTriangle; countKey: string }[] = [
  { id: 'incidentes', label: 'Incidentes', icon: AlertTriangle, countKey: 'incidentesActivos' },
  { id: 'recursos', label: 'Recursos', icon: Ambulance, countKey: 'recursos' },
  { id: 'revision', label: 'Revisión', icon: Hourglass, countKey: 'eventosEnRevision' },
]

export default function GameSidebar({ state }: GameSidebarProps) {
  const [activeTab, setActiveTab] = useState<SidebarTab>('incidentes')

  return (
    <div className="game-sidebar">
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
            >
              <Icon size={12} />
              {tab.label}
              {count > 0 && <span className="sidebar-tab-badge">{count}</span>}
            </button>
          )
        })}
      </div>

      <div className="sidebar-content">
        {activeTab === 'incidentes' && <PanelIncidentes state={state} />}
        {activeTab === 'recursos' && <PanelRecursos state={state} />}
        {activeTab === 'revision' && <PanelEventosRevision state={state} />}
      </div>
    </div>
  )
}
