import { ShieldAlert, Eye, ScrollText } from 'lucide-react'
import PanelPenalizaciones from './PanelPenalizaciones'
import PanelVistas from './PanelVistas'
import PanelLogs from './PanelLogs'

interface GameDrawerProps {
  state: any
  activeTab: string | null
  onTabChange: (tab: string | null) => void
}

const TABS = [
  { id: 'penalizaciones', label: 'Penalizaciones', icon: ShieldAlert },
  { id: 'vistas', label: 'Vistas SQL', icon: Eye },
  { id: 'logs', label: 'Logs', icon: ScrollText },
]

export default function GameDrawer({ state, activeTab, onTabChange }: GameDrawerProps) {
  const isOpen = activeTab !== null

  return (
    <>
      {/* Tab toggle buttons — always visible above hotbar */}
      <div className="drawer-tab-bar">
        {TABS.map((tab) => {
          const Icon = tab.icon
          return (
            <button
              key={tab.id}
              type="button"
              className={`drawer-toggle ${activeTab === tab.id ? 'active' : ''}`}
              onClick={() => onTabChange(activeTab === tab.id ? null : tab.id)}
            >
              <Icon size={11} />
              {tab.label}
            </button>
          )
        })}
      </div>

      {/* Drawer content */}
      <div className={`game-drawer ${isOpen ? 'open' : 'closed'}`}>
        {isOpen && (
          <div className="drawer-content">
            {activeTab === 'penalizaciones' && <PanelPenalizaciones state={state} />}
            {activeTab === 'vistas' && <PanelVistas />}
            {activeTab === 'logs' && <PanelLogs state={state} />}
          </div>
        )}
      </div>
    </>
  )
}
