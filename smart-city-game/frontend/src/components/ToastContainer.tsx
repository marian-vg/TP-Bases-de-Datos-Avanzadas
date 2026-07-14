import { useState, useEffect, useRef } from 'react'
import { Activity, Ambulance, Crosshair, DatabaseZap, Hourglass, RadioTower, X } from 'lucide-react'

const ICONS: Record<string, typeof Activity> = {
  attack: Crosshair,
  sensor: RadioTower,
  operator: Hourglass,
  resource: Ambulance,
  penalty: DatabaseZap,
}

type Toast = {
  id: number
  kind: string
  title: string
  message: string
  severity: string
  simTime: string
  isExiting?: boolean
}

type ToastContainerProps = {
  state: any
}

export default function ToastContainer({ state }: ToastContainerProps) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const seenIdsRef = useRef<Set<number>>(new Set())
  const isInitialRef = useRef<boolean>(true)

  useEffect(() => {
    if (!state?.gameFeed) return

    const feed = state.gameFeed as any[]
    const newItems = feed.filter((item) => !seenIdsRef.current.has(item.id))

    if (newItems.length === 0) return

    // Marcar todos como vistos
    newItems.forEach((item) => seenIdsRef.current.add(item.id))

    // Si es la carga inicial de la aplicación, solo marcamos los existentes como "vistos"
    // para no atiborrar de toasts históricos la primera vez que abre
    if (isInitialRef.current) {
      isInitialRef.current = false
      return
    }

    // Ordenar de más viejo a más nuevo para que se encolen en orden cronológico
    const itemsToAdd = [...newItems].reverse()

    setToasts((prev) => [
      ...prev,
      ...itemsToAdd.map((item) => ({
        id: item.id,
        kind: item.kind,
        title: item.title,
        message: item.message,
        severity: item.severity || 'info',
        simTime: item.sim_time,
      })),
    ])
  }, [state])

  // Desvanecer toasts automáticamente
  useEffect(() => {
    const activeToasts = toasts.filter(t => !t.isExiting)
    if (activeToasts.length === 0) return

    const timers = activeToasts.map(toast => {
      return setTimeout(() => {
        handleTriggerExit(toast.id)
      }, 5000)
    })

    return () => {
      timers.forEach(t => clearTimeout(t))
    }
  }, [toasts])

  const handleTriggerExit = (id: number) => {
    setToasts(prev =>
      prev.map(t => (t.id === id ? { ...t, isExiting: true } : t))
    )
    // Remover definitivamente después de que termine la animación de salida
    setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id))
    }, 300)
  }

  // Resalta entidades conocidas
  const formatMessage = (message: string) => {
    if (!message) return ''
    let html = message

    // 0) Reemplazar zona ID numérico por su nombre descriptivo
    if (state?.zonas) {
      const zoneRegex = /\bzona\s*:?\s*(\d+)\b/gi
      html = html.replace(zoneRegex, (match, zoneIdStr) => {
        const zoneId = parseInt(zoneIdStr, 10)
        const zoneObj = state.zonas.find((z: any) => z.id_zona === zoneId)
        return zoneObj ? `zona ${zoneObj.nombre}` : match
      })
    }

    // 1) Resaltar zonas
    if (state?.zonas) {
      state.zonas.forEach((z: any) => {
        const regex = new RegExp(`\\b${z.nombre}\\b`, 'g')
        html = html.replace(regex, `<span class="toast-highlight toast-highlight--zone">${z.nombre}</span>`)
      })
    }

    // 2) Resaltar recursos (ej: Bomberos #4 o recurso 4)
    html = html.replace(/(Bomberos #\d+|Policía #\d+|Ambulancia #\d+|recurso \d+)/g, '<span class="toast-highlight toast-highlight--resource">$1</span>')

    // 3) Resaltar incidentes/eventos/accidentes
    html = html.replace(/(incidente \d+|evento #\d+|accidente \d+|falla estructural)/gi, '<span class="toast-highlight toast-highlight--incident">$1</span>')

    return <span dangerouslySetInnerHTML={{ __html: html }} />
  }

  if (toasts.length === 0) return null

  return (
    <div className="toasts-wrapper">
      {toasts.map((toast) => {
        const Icon = ICONS[toast.kind] || Activity
        const time = toast.simTime
          ? new Date(toast.simTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
          : '--:--'
        const className = `toast-item toast-item--${toast.severity} ${toast.isExiting ? 'toast-item--exit' : ''}`

        return (
          <div key={toast.id} className={className}>
            <div className="toast-icon">
              <Icon size={16} />
            </div>
            <div className="toast-content">
              <div className="toast-title">
                {toast.title} <span style={{ float: 'right', fontSize: '9px', opacity: 0.5, fontFamily: 'var(--font-mono)', fontWeight: 'normal', marginLeft: '8px', marginTop: '2px' }}>{time}</span>
              </div>
              <div className="toast-msg">{formatMessage(toast.message)}</div>
            </div>
            <button className="toast-close-btn" onClick={() => handleTriggerExit(toast.id)}>
              <X size={14} />
            </button>
          </div>
        )
      })}
    </div>
  )
}
