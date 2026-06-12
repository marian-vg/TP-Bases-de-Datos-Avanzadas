import { useState, useCallback } from 'react'
import { fetchState } from './api/client'
import { usePolling } from './api/polling'
import MapaZonas from './components/MapaZonas'
import Hotbar from './components/Hotbar'
import StatusBar from './components/StatusBar'
import GameTopbar from './components/GameTopbar'
import GameSidebar from './components/GameSidebar'
import GameDrawer from './components/GameDrawer'

function App() {
  const [state, setState] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [selectedCatastrophe, setSelectedCatastrophe] = useState<string | null>(null)
  const [lastTriggered, setLastTriggered] = useState<Record<string, number>>({})
  const [drawerTab, setDrawerTab] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const data = await fetchState()
      setState(data)
      setError(null)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }, [])

  const markCatastropheTriggered = useCallback((catastropheId: string) => {
    setLastTriggered((current) => ({ ...current, [catastropheId]: Date.now() / 1000 }))
  }, [])

  usePolling(load, 1500)

  /* ── Loading screen ── */
  if (loading) {
    return (
      <div className="loading-screen">
        <div className="loading-spinner" />
        <div style={{ color: 'var(--accent-cyan)', fontSize: 13, fontWeight: 700, fontFamily: 'var(--font-mono)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
          Conectando con Pulse City...
        </div>
      </div>
    )
  }

  /* ── Error screen ── */
  if (error && !state) {
    return (
      <div className="error-screen">
        <div style={{ width: 48, height: 48, borderRadius: 8, background: 'rgba(248,113,113,0.1)', border: '1px solid rgba(248,113,113,0.3)', display: 'grid', placeItems: 'center', color: 'var(--accent-red)', fontSize: 24 }}>
          ⚠
        </div>
        <div style={{ color: 'var(--hud-text)', fontSize: 16, fontWeight: 700 }}>
          Pulse City no pudo cargar estado
        </div>
        <div style={{ color: 'var(--hud-text-muted)', fontSize: 12, maxWidth: 400, textAlign: 'center' }}>
          {error}
        </div>
        <button className="sim-btn sim-btn--primary" onClick={load} style={{ marginTop: 8, padding: '6px 16px', fontSize: 13 }}>
          Reintentar
        </button>
      </div>
    )
  }

  return (
    <div className="game-shell">
      <div className="game-backdrop" />

      {/* ── Top bar: logo + metrics ── */}
      <GameTopbar state={state} />

      {/* ── Status bar: sim controls ── */}
      <StatusBar state={state} />

      {/* ── Main area: map + sidebar ── */}
      <div className="game-main">
        <div className="game-map-area">
          {/* Map */}
          <MapaZonas
            state={state}
            selectedCatastrophe={selectedCatastrophe}
            onSelectZoneCatastropheComplete={() => setSelectedCatastrophe(null)}
            onCatastropheTriggered={markCatastropheTriggered}
          />

          {/* Bottom drawer (Penalizaciones / Vistas / Logs) */}
          <GameDrawer
            state={state}
            activeTab={drawerTab}
            onTabChange={setDrawerTab}
          />
        </div>

        {/* Right sidebar (Incidentes / Recursos / Revisión) */}
        <GameSidebar state={state} />
      </div>

      {/* ── Hotbar: catastrophe weapons ── */}
      <Hotbar
        state={state}
        selectedCatastrophe={selectedCatastrophe}
        onSelectCatastrophe={setSelectedCatastrophe}
        lastTriggered={lastTriggered}
      />
    </div>
  )
}

export default App
