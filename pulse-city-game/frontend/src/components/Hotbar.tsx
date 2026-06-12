import { Flame, HeartPulse, Mountain, ShieldAlert, Siren, Waves } from 'lucide-react'
import { cn } from '@/lib/utils'

type HotbarProps = {
  state: any
  selectedCatastrophe: string | null
  onSelectCatastrophe: (value: string | null) => void
  lastTriggered: Record<string, number>
}

const ICONS: Record<string, typeof Flame> = {
  incendio: Flame,
  robo: ShieldAlert,
  accidente: Siren,
  emergencia_medica: HeartPulse,
  falla_estructural: Mountain,
  evento_ambiental: Waves,
}

const GRAVITY_COLORS: Record<number, { bg: string; text: string; border: string }> = {
  5: { bg: 'rgba(248,113,113,0.12)', text: 'var(--accent-red)', border: 'rgba(248,113,113,0.3)' },
  4: { bg: 'rgba(251,191,36,0.1)', text: 'var(--accent-amber)', border: 'rgba(251,191,36,0.25)' },
  3: { bg: 'rgba(56,189,248,0.08)', text: 'var(--accent-cyan)', border: 'rgba(56,189,248,0.2)' },
  2: { bg: 'rgba(52,211,153,0.08)', text: 'var(--accent-emerald)', border: 'rgba(52,211,153,0.2)' },
  1: { bg: 'rgba(74,85,104,0.15)', text: 'var(--hud-text-muted)', border: 'rgba(74,85,104,0.3)' },
}

function getGravityStyle(g: number) {
  return GRAVITY_COLORS[Math.min(5, Math.max(1, g))] || GRAVITY_COLORS[3]
}

export default function Hotbar({ state, selectedCatastrophe, onSelectCatastrophe, lastTriggered }: HotbarProps) {
  const catastrofes = state?.catastrofesList || [
    { id: 'incendio', nombre: 'Incendio', gravedad: 4, cooldown: 20 },
    { id: 'robo', nombre: 'Robo', gravedad: 2, cooldown: 8 },
    { id: 'accidente', nombre: 'Accidente', gravedad: 3, cooldown: 12 },
    { id: 'emergencia_medica', nombre: 'Emergencia Médica', gravedad: 4, cooldown: 18 },
    { id: 'falla_estructural', nombre: 'Falla Estructural', gravedad: 5, cooldown: 30 },
    { id: 'evento_ambiental', nombre: 'Evento Ambiental', gravedad: 3, cooldown: 10 },
  ]

  const now = Date.now() / 1000

  return (
    <div className="game-hotbar">
      <span style={{ fontSize: 10, fontWeight: 700, color: 'var(--hud-text-muted)', textTransform: 'uppercase', letterSpacing: '0.06em', marginRight: 4, flexShrink: 0, fontFamily: 'var(--font-mono)' }}>
        ⚡ Catástrofes
      </span>

      {catastrofes.map((cat: any) => {
        const remaining = Math.max(0, (lastTriggered[cat.id] || 0) + cat.cooldown - now)
        const disabled = remaining > 0
        const isSelected = selectedCatastrophe === cat.id
        const Icon = ICONS[cat.id] || ShieldAlert
        const gStyle = getGravityStyle(cat.gravedad)
        const cooldownRatio = cat.cooldown > 0 ? Math.min(1, remaining / cat.cooldown) : 0

        return (
          <button
            key={cat.id}
            type="button"
            className={cn(
              'hotbar-slot',
              disabled && 'hotbar-slot--disabled',
              isSelected && !disabled && 'hotbar-slot--armed',
            )}
            onClick={() => !disabled && onSelectCatastrophe(isSelected ? null : cat.id)}
          >
            <div className="hotbar-icon" style={{ background: gStyle.bg, color: gStyle.text }}>
              <Icon size={13} />
            </div>
            <span className="hotbar-name">{cat.nombre}</span>
            <span
              className="hotbar-gravity"
              style={{ background: gStyle.bg, color: gStyle.text, border: `1px solid ${gStyle.border}` }}
            >
              G{cat.gravedad}
            </span>
            {disabled && (
              <span style={{ fontSize: 9, fontFamily: 'var(--font-mono)', color: 'var(--accent-red)', fontWeight: 700 }}>
                {remaining.toFixed(0)}s
              </span>
            )}
            {disabled && (
              <div
                className="hotbar-cooldown-bar"
                style={{ width: `${cooldownRatio * 100}%`, background: 'var(--accent-red)' }}
              />
            )}
            {isSelected && !disabled && (
              <div
                className="hotbar-cooldown-bar"
                style={{ width: '100%', background: 'var(--accent-red)', opacity: 0.6 }}
              />
            )}
          </button>
        )
      })}
    </div>
  )
}
